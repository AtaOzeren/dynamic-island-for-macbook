import Foundation
import Testing
@testable import NotchFlowCore

/// The value half of todo 64: what NotchFlow is allowed to do with one music app
/// has to be derivable from that app's permission status alone, so that "no
/// permission is requested at launch" is checkable without a system prompt.
@Suite("MusicAutomationAccess")
struct MusicAutomationTests {
    private static func access(
        _ status: AutomationPermissionStatus,
        target: MusicPlayerTarget = .spotify
    ) -> MusicAutomationAccess {
        MusicAutomationAccess(target: target, status: status)
    }

    // MARK: - Querying

    /// The acceptance criterion "no permission is requested at launch", reduced
    /// to the one line that enforces it: the first Apple Event is what raises
    /// the prompt, so an undecided target must not be queryable.
    @Test("a target with no recorded decision may not be sent an Apple Event")
    func notDeterminedIsNotQueryable() {
        #expect(Self.access(.notDetermined).canQuery == false)
    }

    @Test("only a granted target may be sent an Apple Event")
    func onlyGrantedIsQueryable() {
        #expect(Self.access(.granted).canQuery)
        #expect(Self.access(.denied).canQuery == false)
    }

    // MARK: - Requesting

    @Test("only an undecided target can be asked about")
    func onlyNotDeterminedIsRequestable() {
        #expect(Self.access(.notDetermined).isRequestable)
        #expect(Self.access(.granted).isRequestable == false)
        #expect(Self.access(.denied).isRequestable == false)
    }

    /// The no-nagging half of step 4: a denied row offers no button, because the
    /// system would swallow the re-prompt and the only real remedy is the System
    /// Settings path the explanation names.
    @Test("a button is offered only where a prompt would actually appear")
    func actionTitleExistsOnlyWhenRequestable() {
        #expect(Self.access(.notDetermined).actionTitle != nil)
        #expect(Self.access(.granted).actionTitle == nil)
        #expect(Self.access(.denied).actionTitle == nil)
    }

    @Test("the button names the app it will ask about")
    func actionTitleNamesTheTarget() {
        #expect(Self.access(.notDetermined, target: .spotify).actionTitle?.contains("Spotify") == true)
        #expect(Self.access(.notDetermined, target: .appleMusic).actionTitle?.contains("Music") == true)
    }

    // MARK: - Explanation

    /// Step 2 of the flow requires NotchFlow's own explanation before the system
    /// prompt, and every state has to say what is true now rather than share one
    /// hedged sentence.
    @Test("each status explains itself, naming the app")
    func everyStatusExplainsItself() {
        let explanations = [
            Self.access(.notDetermined).explanation,
            Self.access(.granted).explanation,
            Self.access(.denied).explanation
        ]

        for explanation in explanations {
            #expect(explanation.isEmpty == false)
            #expect(explanation.contains("Spotify"))
        }
        #expect(Set(explanations).count == explanations.count)
    }

    /// A denied row has to say the rest of the app is unaffected — that sentence
    /// is the user-visible form of "denying any permission disables only the
    /// dependent feature".
    @Test("the denied explanation points at System Settings and reassures")
    func deniedExplanationNamesTheRemedy() {
        let explanation = Self.access(.denied).explanation
        #expect(explanation.contains("System Settings"))
        #expect(explanation.contains("Automation"))
        #expect(explanation.contains("keeps working"))
    }

    // MARK: - Targets

    @Test("the two scriptable targets are unchanged by the permission work")
    func targetsAreSpotifyAndAppleMusic() {
        #expect(MusicPlayerTarget.allCases == [.spotify, .appleMusic])
        #expect(MusicPlayerTarget.spotify.bundleIdentifier == "com.spotify.client")
        #expect(MusicPlayerTarget.appleMusic.bundleIdentifier == "com.apple.Music")
    }
}
