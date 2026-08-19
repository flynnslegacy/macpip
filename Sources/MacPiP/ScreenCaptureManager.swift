import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit

@MainActor
final class ScreenCaptureManager: NSObject {
    private var stream: SCStream?
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private var hasDeliveredFirstFrame = false

    var isCapturing: Bool { stream != nil }

    var onFirstFrame: (() -> Void)?
    var onStop: ((String) -> Void)?

    /// Last known window list, kept warm by `refreshWindowCache()` so the
    /// right-click menu can pop up instantly instead of waiting on a fresh,
    /// content-probing scan (which takes a few hundred ms and would make the
    /// menu feel laggy every time).
    private(set) var cachedWindows: [SCWindow] = []
    private(set) var cacheError: Error?
    private var refreshTask: Task<Void, Never>?

    /// Kicks off (or no-ops if one is already running) a background scan that
    /// updates `cachedWindows`. Call this ahead of time (app launch) and again
    /// after every menu open, so the *next* open already has fresh data.
    func refreshWindowCache() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let windows = try await self.listCapturableWindows()
                self.cachedWindows = windows
                self.cacheError = nil
            } catch {
                self.cacheError = error
            }
            self.refreshTask = nil
        }
    }

    func listCapturableWindows() async throws -> [SCWindow] {
        // onScreenWindowsOnly: false — a window in a fullscreen Space (e.g. Plex,
        // Apple TV playing fullscreen) is not "on screen" from the current Space's
        // point of view, so it would otherwise be missing from the list. The
        // desktopIndependentWindow filter used in startCapture can still capture it.
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // Note: we deliberately do NOT probe windows with a throwaway SCStream to
        // check for real content (a previous version of this code did). Each probe
        // is its own capture session outside the system's picker UI, and macOS
        // treats every one of those as a "bypassing the system picker" event —
        // with dozens of windows on screen, that meant dozens of repeated system
        // permission dialogs. Static, metadata-only filtering is the trade-off:
        // an app with several real windows (Plex included) may still list more
        // than one option, but only picking one ever opens a capture session.
        return content.windows
            .filter { $0.owningApplication?.processID != ownPID }
            .filter { $0.owningApplication != nil }
            .filter { $0.windowLayer == 0 }
            .filter { $0.frame.width > 100 && $0.frame.height > 100 }
            .filter { window in
                // Only list windows from regular, user-facing apps — this excludes
                // helper/agent processes (Safari/Chrome AutoFill popovers, save-panel
                // services, menu-bar-only agents) that technically own a window but
                // aren't something the user would think of as "an application".
                guard let pid = window.owningApplication?.processID else { return false }
                return NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            }
            .filter { Self.isLikelyContentWindow($0, metadataByWindowID: Self.currentWindowMetadata()) }
            .sorted {
                ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "")
            }
    }

    private struct WindowMetadata {
        var alpha: Double
        var isOnscreen: Bool
        var isShareable: Bool
    }

    /// Some apps (Plex included) keep hidden or non-shareable windows around
    /// (preload buffers, offscreen webviews) that pass every other filter but
    /// never show anything if captured. None of this needs a capture session —
    /// it's a plain metadata query against the Quartz window list:
    ///  - alpha 0 → invisible, nothing would ever show.
    ///  - not onscreen → not actually composited right now (e.g. minimized).
    ///  - sharing state "none" → the window explicitly opted out of being
    ///    recorded/shared, which real content windows essentially never do.
    private static func currentWindowMetadata() -> [CGWindowID: WindowMetadata] {
        guard let infoList = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var result: [CGWindowID: WindowMetadata] = [:]
        for info in infoList {
            guard let numberValue = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let isOnscreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
            let sharingState = (info[kCGWindowSharingState as String] as? NSNumber)?.intValue ?? 1
            result[CGWindowID(numberValue.uint32Value)] = WindowMetadata(
                alpha: alpha,
                isOnscreen: isOnscreen,
                isShareable: sharingState != 0
            )
        }
        return result
    }

    private static func isLikelyContentWindow(_ window: SCWindow, metadataByWindowID: [CGWindowID: WindowMetadata]) -> Bool {
        guard let metadata = metadataByWindowID[window.windowID] else { return true }
        return metadata.alpha > 0.01 && metadata.isOnscreen && metadata.isShareable
    }

    /// Tries each window in order using the real display stream (no throwaway
    /// probes) until one actually delivers content, then leaves that one
    /// running. This is how we resolve apps like Plex that own several windows
    /// but only one of them ever renders anything — without spinning up extra
    /// capture sessions ahead of time just to check.
    func startCapture(candidates: [SCWindow], displayLayer: AVSampleBufferDisplayLayer) async {
        guard !candidates.isEmpty else { return }
        await stopCapture()
        self.displayLayer = displayLayer

        for window in candidates {
            hasDeliveredFirstFrame = false
            await startSingleStream(window: window)

            let deadline = Date().addingTimeInterval(1.2)
            while !hasDeliveredFirstFrame && Date() < deadline {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }

            if hasDeliveredFirstFrame {
                return
            }

            if let currentStream = stream {
                stream = nil
                try? await currentStream.stopCapture()
            }
        }

        onStop?(String(localized: "Aucune de ces fenêtres n'affiche de contenu pour le moment.", comment: "Shown when none of the candidate windows for a picked app produced real content"))
    }

    private func startSingleStream(window: SCWindow) async {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = max(Int(NSScreen.main?.backingScaleFactor ?? 2), 1)
        configuration.width = max(Int(window.frame.width) * scale, 2)
        configuration.height = max(Int(window.frame.height) * scale, 2)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.showsCursor = true
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            try await newStream.startCapture()
            stream = newStream
        } catch {
            // Leave `stream` nil — the caller's loop will just move on to the
            // next candidate window.
        }
    }

    func stopCapture() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
        displayLayer?.flushAndRemoveImage()
    }
}

extension ScreenCaptureManager: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(sampleBuffer) else { return }
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRawValue = attachmentsArray.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue),
              status == .complete else { return }

        Task { @MainActor in
            guard let layer = self.displayLayer else { return }
            if layer.status == .failed {
                layer.flush()
            }
            layer.enqueue(sampleBuffer)
            if !self.hasDeliveredFirstFrame {
                self.hasDeliveredFirstFrame = true
                self.onFirstFrame?()
            }
        }
    }
}

extension ScreenCaptureManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            let template = String(localized: "Capture arrêtée : %@", comment: "%@ is the underlying system error description")
            self.onStop?(String(format: template, error.localizedDescription))
        }
    }
}
