import AppKit
import NotchFlowCore
import NotchFlowUI
import SwiftUI

/// Puts the first-run sequence on screen, once.
///
/// It is an `NSWindow` rather than a SwiftUI `Window` scene because NotchFlow is
/// an accessory app: a scene-managed window inherits state restoration, which
/// would bring onboarding back after a relaunch that the `hasCompletedOnboarding`
/// flag says is not a first run. Owning the window here makes "shown exactly
/// once" a property of the flag alone.
///
/// The presenter requests no permission and installs nothing. It reports the
/// user's decisions to the composition root, which is the only place that acts
/// on them.
@MainActor
final class OnboardingPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onFinish: ((OnboardingOutcome) -> Void)?

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
        window.title = "Welcome to NotchFlow"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentViewController = NSHostingController(
            rootView: OnboardingRoot(
                initialFlow: OnboardingFlow(detectedAgents: detectedAgents()),
                onOpenSettings: Self.openSettings,
                onFinish: { [weak self] outcome in
                    self?.complete(with: outcome)
                }
            )
        )
        window.center()
        self.window = window

        // An accessory app has no Dock icon to click, so nothing would bring the
        // window forward on its own. This is the one moment NotchFlow needs the
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

    /// The same action ⌘, and the status item send, so onboarding's last step
    /// opens the one settings window rather than a second copy of it.
    private static func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
