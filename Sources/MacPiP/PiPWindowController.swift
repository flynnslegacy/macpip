import AppKit

final class PiPWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 270),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "AnyPiP"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.minSize = NSSize(width: 240, height: 135)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // The traffic-light buttons are required by App Review (Apple rejected a
        // borderless window with none), but a floating PiP window looks best
        // without them cluttering the view permanently — PiPView reveals them
        // on hover and hides them again once the mouse leaves.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.alphaValue = 0
        }
        window.center()

        let pipView = PiPView(frame: NSRect(origin: .zero, size: window.frame.size))
        pipView.autoresizingMask = [.width, .height]
        window.contentView = pipView

        self.init(window: window)
    }
}
