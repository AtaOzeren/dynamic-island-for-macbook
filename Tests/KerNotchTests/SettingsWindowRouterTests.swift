import AppKit
import Testing

@testable import KerNotch

/// The two pure halves of `SettingsWindowRouter`: finding the item the
/// SwiftUI `Settings` scene installs, and picking the scene's window out of
/// the app's window list. The open/retry loop itself drives the live
/// `NSApplication` and is exercised by hand drills, not here.
@Suite("Settings window router")
@MainActor
struct SettingsWindowRouterTests {
    private func titledWindow(identifier: String? = nil) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        if let identifier {
            window.identifier = NSUserInterfaceItemIdentifier(rawValue: identifier)
        }
        return window
    }

    private func appMenu() -> NSMenu {
        // The shape SwiftUI builds: an empty main menu whose first item's
        // submenu is the application menu holding the Settings item.
        let applicationSubmenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: nil,
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        applicationSubmenu.addItem(settingsItem)

        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationSubmenu
        mainMenu.addItem(applicationItem)
        return mainMenu
    }

    @Test("finds the ⌘, item inside the application submenu")
    func findsSettingsMenuItem() {
        let item = SettingsWindowRouter.settingsMenuItem(in: appMenu())
        #expect(item?.keyEquivalent == ",")
    }

    @Test("finds nothing when no ⌘, item exists")
    func findsNoSettingsMenuItemWithoutMatch() {
        let mainMenu = NSMenu()
        let submenu = NSMenu()
        submenu.addItem(NSMenuItem(title: "Quit", action: nil, keyEquivalent: "q"))
        let root = NSMenuItem()
        root.submenu = submenu
        mainMenu.addItem(root)

        #expect(SettingsWindowRouter.settingsMenuItem(in: mainMenu) == nil)
    }

    @Test("a comma bound to another modifier is not the settings item")
    func skipsCommaWithOtherModifier() {
        let submenu = NSMenu()
        let item = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: ",")
        item.keyEquivalentModifierMask = .option
        submenu.addItem(item)
        let mainMenu = NSMenu()
        let root = NSMenuItem()
        root.submenu = submenu
        mainMenu.addItem(root)

        #expect(SettingsWindowRouter.settingsMenuItem(in: mainMenu) == nil)
    }

    /// On a Turkish keyboard the item SwiftUI installs reads back its key
    /// equivalent as `"ö"`, not `","` — the exact defect that made Settings
    /// silently never open on that layout. The item is still found there,
    /// through the layout-independent action SwiftUI gives it.
    @Test("the item is found by action when the layout localizes its key")
    func findsSettingsMenuItemByActionOnLocalizedLayout() {
        let submenu = NSMenu()
        let item = NSMenuItem(
            title: "Settings…",
            action: Selector(("menuAction:")),
            keyEquivalent: "ö"
        )
        item.keyEquivalentModifierMask = .command
        submenu.addItem(item)
        let mainMenu = NSMenu()
        let root = NSMenuItem()
        root.submenu = submenu
        mainMenu.addItem(root)

        #expect(SettingsWindowRouter.settingsMenuItem(in: mainMenu) === item)
    }

    @Test("picks the Settings scene window over unidentifed windows")
    func picksSettingsWindowByIdentifier() {
        let onboarding = titledWindow()
        let manualSetup = titledWindow()
        let settings = titledWindow(identifier: "com.apple.SwiftUI.Settings window")

        let found = SettingsWindowRouter.settingsWindow(in: [onboarding, manualSetup, settings])

        #expect(found === settings)
    }

    @Test("no match when only the app's own windows exist")
    func noSettingsWindowAmongUnidentified() {
        let onboarding = titledWindow()

        #expect(SettingsWindowRouter.settingsWindow(in: [onboarding]) == nil)
    }

    @Test("an identified window above the normal level is not the scene's")
    func ignoresIdentifiedFloatingWindow() {
        let floating = titledWindow(identifier: "com.apple.SwiftUI.Settings window")
        floating.level = .floating

        #expect(SettingsWindowRouter.settingsWindow(in: [floating]) == nil)
    }

    @Test("the identifier match is case-insensitive")
    func matchesIdentifierCaseInsensitively() {
        let settings = titledWindow(identifier: "COM.APPLE.SWIFTUI.SETTINGS WINDOW")

        #expect(SettingsWindowRouter.settingsWindow(in: [settings]) === settings)
    }
}
