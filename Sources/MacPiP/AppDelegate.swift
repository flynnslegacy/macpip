import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var windowController: PiPWindowController?

    private let authorName = "David Markowicz"
    private let websiteURLString = "https://anypip.exemples.xyz"
    private let donationURLString = "https://buymeacoffee.com/davidmarkowicz"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusItem()
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(
            title: String(localized: "À propos de AnyPiP", comment: "App menu item: show the About panel"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let donateItem = NSMenuItem(
            title: String(localized: "Faire un don ❤️", comment: "App menu item: open the donation page"),
            action: #selector(openDonationPage),
            keyEquivalent: ""
        )
        donateItem.target = self
        appMenu.addItem(donateItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quitter", comment: "Menu bar item: quit the app"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.loadMenuBarIcon()

        let menu = NSMenu()

        let relaunchItem = NSMenuItem(
            title: String(localized: "Relancer", comment: "Menu bar item: reopen the PiP window if it was closed"),
            action: #selector(showWindow),
            keyEquivalent: ""
        )
        relaunchItem.target = self
        menu.addItem(relaunchItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: String(localized: "À propos de AnyPiP", comment: "Menu bar item: show the About panel"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let donateItem = NSMenuItem(
            title: String(localized: "Faire un don ❤️", comment: "Menu bar item: open the donation page"),
            action: #selector(openDonationPage),
            keyEquivalent: ""
        )
        donateItem.target = self
        menu.addItem(donateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quitter", comment: "Menu bar item: quit the app"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func showWindow() {
        if windowController == nil {
            windowController = PiPWindowController()
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDonationPage() {
        if let url = URL(string: donationURLString) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showAbout() {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "AnyPiP",
            .applicationVersion: shortVersion,
            .version: buildVersion,
            .credits: Self.buildCredits(author: authorName, website: websiteURLString)
        ]
        if let icon = Self.loadMenuBarIcon()?.copy() as? NSImage {
            icon.isTemplate = false
            options[.applicationIcon] = icon
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    private static func loadMenuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "pip", accessibilityDescription: "AnyPiP")
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private static func buildCredits(author: String, website: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let text = NSMutableAttributedString(
            string: "\(author)\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor
            ]
        )

        if let url = URL(string: website) {
            text.append(NSAttributedString(
                string: website,
                attributes: [.font: NSFont.systemFont(ofSize: 11), .link: url]
            ))
        } else {
            text.append(NSAttributedString(string: website, attributes: [.font: NSFont.systemFont(ofSize: 11)]))
        }

        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        return text
    }
}
