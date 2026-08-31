import NotchFlowCore
import SwiftUI

/// The onboarding window's fixed visual budget, the first-run counterpart to
/// `SettingsPaneMetrics` — one edit changes every step's density.
///
/// It is separate from the settings metrics because the two surfaces have
/// different jobs: onboarding is a wider, more spacious reading screen with a
/// fixed height so stepping forward never resizes the window, while a settings
/// pane is a dense control list that scrolls.
public struct OnboardingMetrics: Equatable, Sendable {
    public static let `default` = OnboardingMetrics()

    public let contentInset: CGFloat
    public let sectionSpacing: CGFloat
    public let rowSpacing: CGFloat
    public let titleSize: CGFloat
    public let bodySize: CGFloat
    public let footnoteSize: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(
        contentInset: CGFloat = 28,
        sectionSpacing: CGFloat = 18,
        rowSpacing: CGFloat = 10,
        titleSize: CGFloat = 22,
        bodySize: CGFloat = 13,
        footnoteSize: CGFloat = 11,
        width: CGFloat = 480,
        height: CGFloat = 420
    ) {
        self.contentInset = contentInset
        self.sectionSpacing = sectionSpacing
        self.rowSpacing = rowSpacing
        self.titleSize = titleSize
        self.bodySize = bodySize
        self.footnoteSize = footnoteSize
        self.width = width
        self.height = height
    }
}

/// What onboarding hands back when it closes: the flag to persist, and the hook
/// installs the user explicitly accepted.
///
/// The view reports rather than acts. Installing a hook needs the file system
/// seam that lives in `NotchFlowProviders`, and routing the decision through the
/// composition root keeps this screen's consent flow identical to the one
/// Settings uses later — the same offer, resolved by the same installer.
public struct OnboardingOutcome: Equatable, Sendable {
    public let acceptedHookOffers: [IPCAgentID]
    public let wasSkipped: Bool

    public init(acceptedHookOffers: [IPCAgentID], wasSkipped: Bool) {
        self.acceptedHookOffers = acceptedHookOffers
        self.wasSkipped = wasSkipped
    }
}

/// Owns the flow value for a hosted onboarding window.
///
/// `OnboardingWindowView` takes a binding for the same reason every settings
/// pane does — a view holding its own copy cannot be driven or inspected
/// outside a rendered hierarchy. This wrapper is the one place that storage
/// lives when the window has no composition root above it to hold it.
public struct OnboardingRoot: View {
    @State private var flow: OnboardingFlow

    private let metrics: OnboardingMetrics
    private let onFinish: (OnboardingOutcome) -> Void
    private let onOpenSettings: () -> Void

    public init(
        initialFlow: OnboardingFlow,
        metrics: OnboardingMetrics = .default,
        onOpenSettings: @escaping () -> Void = {},
        onFinish: @escaping (OnboardingOutcome) -> Void
    ) {
        _flow = State(initialValue: initialFlow)
        self.metrics = metrics
        self.onOpenSettings = onOpenSettings
        self.onFinish = onFinish
    }

    public var body: some View {
        OnboardingWindowView(
            flow: $flow,
            metrics: metrics,
            onOpenSettings: onOpenSettings,
            onFinish: onFinish
        )
    }
}

/// The first-run sequence: welcome, permission explanation, agent detection and
/// hook offer, done.
///
/// The view renders `OnboardingFlow` and requests nothing of the system. Every
/// permission stays lazy — the second step only *describes* what will later be
/// asked for, and the third records a decision the composition root acts on
/// after the window closes, which is what makes "never requests a permission the
/// user has not opted into" true by construction rather than by review.
public struct OnboardingWindowView: View {
    @Binding private var flow: OnboardingFlow

    private let metrics: OnboardingMetrics
    private let onFinish: (OnboardingOutcome) -> Void
    private let onOpenSettings: () -> Void

    public init(
        flow: Binding<OnboardingFlow>,
        metrics: OnboardingMetrics = .default,
        onOpenSettings: @escaping () -> Void = {},
        onFinish: @escaping (OnboardingOutcome) -> Void
    ) {
        _flow = flow
        self.metrics = metrics
        self.onOpenSettings = onOpenSettings
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            step(for: flow.step)
            Spacer(minLength: 0)
            Divider()
            navigation
        }
        .padding(metrics.contentInset)
        .frame(width: metrics.width, height: metrics.height, alignment: .leading)
    }

    @ViewBuilder
    private func step(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome: welcomeStep
        case .permissions: permissionsStep
        case .agents: agentsStep
        case .done: doneStep
        }
    }

    private var welcomeStep: some View {
        heading(
            title: localized("Welcome to NotchFlow"),
            body: localized(
                """
                NotchFlow turns the area around your notch into a live activity \
                surface: what is playing, running timers, screen and audio recording \
                indicators, charging state, and the status of your AI coding agents.
                """)
        )
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            heading(
                title: localized("Permissions come later"),
                body: localized(
                    """
                    NotchFlow asks for nothing right now. Each permission is \
                    requested only when you turn on the feature that needs it, and \
                    only after NotchFlow explains what it is about to ask for.
                    """)
            )
            bullet(localized("Apple Events, so now playing and playback controls work with Spotify and Apple Music."))
            bullet(localized("Write access to an agent's configuration file, only when you install its hook."))
            bullet(localized("Recording and charging indicators need no permission at all."))
        }
    }

    private var agentsStep: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            heading(
                title: localized("AI coding agents"),
                body: agentsBodyText
            )
            ForEach(flow.detectedAgents, id: \.self) { agentID in
                Toggle(
                    localized("Show \(agentID.displayName) status in the notch"),
                    isOn: hookOffer(for: agentID)
                )
                .toggleStyle(.switch)
                .font(.system(size: metrics.bodySize))
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            heading(
                title: localized("You are set up"),
                body: localized(
                    """
                    NotchFlow lives in the menu bar. Everything you just saw — \
                    and everything you skipped — can be changed at any time in \
                    Settings.
                    """)
            )
            Button(localized("Open Settings"), action: onOpenSettings)
                .font(.system(size: metrics.bodySize))
        }
    }

    /// Named so the third step reads honestly whether or not detection found
    /// anything: an empty list is a normal outcome, not an error to hide.
    private var agentsBodyText: String {
        flow.detectedAgents.isEmpty
            ? localized(
                """
                No agent configuration was found for Claude Code, Codex CLI, or \
                OpenCode. You can install a hook later from Settings once one is \
                set up.
                """)
            : localized(
                """
                NotchFlow found configuration for the agents below. Turning one \
                on here only records that you want it — nothing is written to \
                any file. Installing the hook itself happens in Settings, where \
                you see the exact snippet and approve the write.
                """)
    }

    private func heading(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            Text(title)
                .font(.system(size: metrics.titleSize, weight: .semibold))
            Text(body)
                .font(.system(size: metrics.bodySize))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ text: String) -> some View {
        Label(text, systemImage: "circle.fill")
            .labelStyle(.titleAndIcon)
            .font(.system(size: metrics.footnoteSize))
            .foregroundStyle(.secondary)
            .imageScale(.small)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var navigation: some View {
        HStack(spacing: metrics.rowSpacing) {
            if flow.canGoBack {
                Button(localized("Back"), action: goBack)
            }
            Spacer()
            if !flow.isOnFinalStep {
                Button(localized("Skip"), action: skip)
            }
            Button(primaryButtonTitle, action: advance)
                .keyboardShortcut(.defaultAction)
        }
        .font(.system(size: metrics.bodySize))
    }

    // MARK: - Driveable surface

    /// The step showing right now. Exposed with the actions below so a test can
    /// walk the whole flow without a window server, the same way
    /// `AIIntegrationsSettingsView` exposes its bindings.
    public var currentStep: OnboardingStep {
        flow.step
    }

    public var primaryButtonTitle: String {
        flow.isOnFinalStep ? localized("Done") : localized("Continue")
    }

    public var isSkippable: Bool {
        !flow.isOnFinalStep
    }

    public var detectedAgents: [IPCAgentID] {
        flow.detectedAgents
    }

    public func hookOffer(for agentID: IPCAgentID) -> Binding<Bool> {
        Binding(
            get: { flow.isAccepted(agentID) },
            set: { flow.setHookOffer(agentID, accepted: $0) }
        )
    }

    public func advance() {
        finish(wasSkipped: false) { $0.advance() }
    }

    public func goBack() {
        flow.goBack()
    }

    public func skip() {
        finish(wasSkipped: true) { $0.skip() }
    }

    /// Reports the outcome on the edit that completes the flow, and only that
    /// one. A second `Done` press — or a close arriving behind one — must not
    /// hand the composition root a duplicate set of hook installs to run.
    private func finish(wasSkipped: Bool, _ edit: (inout OnboardingFlow) -> Void) {
        let wasComplete = flow.isComplete
        edit(&flow)
        guard !wasComplete, flow.isComplete else { return }
        onFinish(
            OnboardingOutcome(
                acceptedHookOffers: flow.acceptedHookOffers,
                wasSkipped: wasSkipped
            )
        )
    }
}
