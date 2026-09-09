import AppKit
import KerNotchCore
import KerNotchUI
import SwiftUI

/// Puts the first-run sequence on screen, once.
///
/// It is an `NSWindow` rather than a SwiftUI `Window` scene because KerNotch is
/// an accessory app: a scene-managed window inherits state restoration, which
/// would bring onboarding back after a relaunch that the `hasCompletedOnboarding`
/// flag says is not a first run. Owning the window here makes "shown exactly
/// once" a property of the flag alone.
///
/// Presenter requests no permission itself. It reports explicit hook approvals
/// to composition root, which performs file-system mutations after flow closes.
@MainActor
final class OnboardingPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onFinish: ((OnboardingOutcome) -> Void)?
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
    }

    /// Shows the flow, or does nothing if this is not a first run.
    ///
    /// The flag is the single gate. Detection runs only when the window is
    /// actually going to open, so a returning user pays no file-system probe.
    func presentIfNeeded(
        hasCompletedOnboarding: Bool,
        detectedAgents: @autoclosure () -> [IPCAgentID],
        onFinish: @escaping (OnboardingOutcome) -> Void
    ) {
        guard !hasCompletedOnboarding, window == nil else { return }
        self.onFinish = onFinish

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Welcome to KerNotch")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingRoot(
                initialFlow: OnboardingFlow(detectedAgents: detectedAgents()),
                onOpenSettings: openSettings,
                onFinish: { [weak self] outcome in
                    self?.complete(with: outcome)
                }
            )
        )
        window.center()
        self.window = window

        // An accessory app has no Dock icon to click, so nothing would bring the
        // window forward on its own. This is the one moment KerNotch needs the
        // user's attention; the activation policy itself is untouched.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closing the window with the title bar button is the same answer as
    /// skipping: the user is done with the flow, and it must not reappear.
    func windowWillClose(_ notification: Notification) {
        complete(with: OnboardingOutcome(acceptedHookOffers: [], wasSkipped: true))
    }

    private func complete(with outcome: OnboardingOutcome) {
        guard let onFinish else { return }
        self.onFinish = nil
        onFinish(outcome)

        let closingWindow = window
        window = nil
        closingWindow?.delegate = nil
        closingWindow?.close()
    }

}

/// Retains manual hook instructions window for automatic-install failures and
/// unreadable configurations reached from Settings.
@MainActor
final class ManualSetupPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func present(_ instructions: ManualSetupInstructions) {
        window?.close()

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = instructions.title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: ManualSetupView(instructions: instructions)
        )
        window.center()
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        window = nil
    }
}
