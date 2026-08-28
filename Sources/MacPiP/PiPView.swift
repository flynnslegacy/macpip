import AppKit
import AVFoundation
import ScreenCaptureKit

@MainActor
final class PiPView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let placeholderLabel = NSTextField(labelWithString: PiPView.chooseWindowPlaceholder)
    private let captureManager = ScreenCaptureManager()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 12
        layer?.masksToBounds = true

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)

        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.alignment = .center
        placeholderLabel.font = .systemFont(ofSize: 13)
        placeholderLabel.isBezeled = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.isEditable = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])

        captureManager.onFirstFrame = { [weak self] in
            self?.placeholderLabel.isHidden = true
        }
        captureManager.onStop = { [weak self] message in
            self?.placeholderLabel.stringValue = message
            self?.placeholderLabel.isHidden = false
        }

        // Warm the window cache right away so the very first right-click
        // doesn't have to wait on it either.
        captureManager.refreshWindowCache()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        setTitleBarButtonsVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        setTitleBarButtonsVisible(false)
    }

    private func setTitleBarButtonsVisible(_ visible: Bool) {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.animator().alphaValue = visible ? 1 : 0
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let menu = buildCaptureMenu()
        // Refresh now so the *next* right-click already has an up-to-date list —
        // this click uses whatever was already cached, so it opens instantly.
        captureManager.refreshWindowCache()
        menu.popUp(positioning: nil, at: location, in: self)
    }

    private func buildCaptureMenu() -> NSMenu {
        let menu = NSMenu()

        // Kept at the very top and always reachable from the window itself.
        // This only hides the window — it does not quit the app, which keeps
        // running in the menu bar (the menu bar's "Quitter" is the only thing
        // that actually terminates it).
        let closeItem = NSMenuItem(
            title: String(localized: "Fermer la fenêtre", comment: "Right-click menu: close the PiP window without quitting the app"),
            action: #selector(closeWindow),
            keyEquivalent: ""
        )
        closeItem.target = self
        menu.addItem(closeItem)
        menu.addItem(.separator())

        let windows = captureManager.cachedWindows

        if windows.isEmpty, captureManager.cacheError != nil {
            let item = menu.addItem(
                withTitle: String(
                    localized: "Autorisation d'enregistrement d'écran requise — cliquer pour ouvrir Réglages",
                    comment: "Right-click menu item shown when Screen Recording permission hasn't been granted"
                ),
                action: #selector(openScreenRecordingSettings),
                keyEquivalent: ""
            )
            item.target = self
        } else if windows.isEmpty {
            let item = menu.addItem(
                withTitle: String(localized: "Recherche des fenêtres en cours…", comment: "Right-click menu item shown while the window list is still loading"),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
        } else {
            var iconCache: [pid_t: NSImage] = [:]
            let groups = Dictionary(grouping: windows) { $0.owningApplication?.processID ?? 0 }
            let orderedGroups = groups.values.sorted {
                ($0.first?.owningApplication?.applicationName ?? "") < ($1.first?.owningApplication?.applicationName ?? "")
            }

            for group in orderedGroups {
                let appName = group.first?.owningApplication?.applicationName
                    ?? String(localized: "Application", comment: "Fallback name when a window's owning app name is unknown")
                let icon = Self.icon(forProcessID: group.first?.owningApplication?.processID, cache: &iconCache)

                if group.count == 1, let window = group.first {
                    let item = NSMenuItem(title: appName, action: #selector(selectWindow(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = [window]
                    item.image = icon
                    menu.addItem(item)
                } else {
                    // Several windows for the same app (e.g. multiple Chrome
                    // windows, or an app like Plex that keeps decoy windows
                    // around) — group them under a submenu. Whichever one is
                    // clicked is tried first; if it turns out blank,
                    // startCapture(candidates:) automatically falls back to
                    // the rest of the group in order.
                    let parentItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
                    parentItem.image = icon
                    let submenu = NSMenu()
                    for window in group {
                        let title = (window.title?.isEmpty == false)
                            ? window.title!
                            : String(localized: "Fenêtre sans titre", comment: "Fallback window title when a window has none")
                        let subItem = NSMenuItem(title: title, action: #selector(selectWindow(_:)), keyEquivalent: "")
                        subItem.target = self
                        let rest = group.filter { $0.windowID != window.windowID }
                        subItem.representedObject = [window] + rest
                        subItem.image = icon
                        submenu.addItem(subItem)
                    }
                    parentItem.submenu = submenu
                    menu.addItem(parentItem)
                }
            }
        }

        if captureManager.isCapturing {
            menu.addItem(.separator())
            let stopItem = NSMenuItem(
                title: String(localized: "Arrêter la capture", comment: "Right-click menu: stop the active capture"),
                action: #selector(stopCapture),
                keyEquivalent: ""
            )
            stopItem.target = self
            menu.addItem(stopItem)
        }

        menu.addItem(.separator())
        let donateItem = NSMenuItem(
            title: String(localized: "Faire un don ❤️", comment: "Right-click menu: open the donation page"),
            action: #selector(openDonationPage),
            keyEquivalent: ""
        )
        donateItem.target = self
        menu.addItem(donateItem)

        return menu
    }

    @objc private func closeWindow() {
        window?.close()
    }

    @objc private func selectWindow(_ sender: NSMenuItem) {
        guard let candidates = sender.representedObject as? [SCWindow], !candidates.isEmpty else { return }
        placeholderLabel.stringValue = String(localized: "Connexion…", comment: "Placeholder text shown while a capture is starting")
        placeholderLabel.isHidden = false
        Task {
            await captureManager.startCapture(candidates: candidates, displayLayer: displayLayer)
        }
    }

    @objc private func stopCapture() {
        Task {
            await captureManager.stopCapture()
        }
        placeholderLabel.stringValue = Self.chooseWindowPlaceholder
        placeholderLabel.isHidden = false
    }

    @objc private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openDonationPage() {
        if let url = URL(string: "https://buymeacoffee.com/davidmarkowicz") {
            NSWorkspace.shared.open(url)
        }
    }

    private static var chooseWindowPlaceholder: String {
        String(localized: "Clic droit pour choisir une fenêtre à capturer", comment: "Placeholder text shown before any capture is active")
    }

    private static func icon(forProcessID pid: pid_t?, cache: inout [pid_t: NSImage]) -> NSImage? {
        guard let pid else { return nil }
        if let cached = cache[pid] {
            return cached
        }
        guard let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        let resized = resizedIcon(icon, to: NSSize(width: 16, height: 16))
        cache[pid] = resized
        return resized
    }

    private static func resizedIcon(_ icon: NSImage, to size: NSSize) -> NSImage {
        let resized = NSImage(size: size)
        resized.lockFocus()
        icon.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        resized.unlockFocus()
        return resized
    }
}
