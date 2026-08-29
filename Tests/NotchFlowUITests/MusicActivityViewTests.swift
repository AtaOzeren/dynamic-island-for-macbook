import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import NotchFlowCore
@testable import NotchFlowUI

@Suite("MusicActivityView")
@MainActor
struct MusicActivityViewTests {
    private static func activity(
        title: String = "Windowlicker",
        artist: String = "Aphex Twin",
        state: MusicPlaybackState = .playing,
        source: String? = "Spotify"
    ) -> MusicActivity {
        MusicActivity(
            nowPlaying: NowPlaying(
                title: title,
                artist: artist,
                playbackState: state,
                sourceApplicationName: source
            )
        )
    }

    // MARK: - The view model

    @Test("draws the track title and artist from the activity")
    func rendersTitleAndArtist() {
        let presentation = MusicPresentation(activity: Self.activity())

        #expect(presentation.title == "Windowlicker")
        #expect(presentation.subtitle == "Aphex Twin")
    }

    /// A backend that reports a title but no artist must not draw a dangling
    /// separator or an empty second line.
    @Test("omits the subtitle when the backend reports no artist")
    func omitsEmptySubtitle() {
        #expect(MusicPresentation(activity: Self.activity(artist: "")).subtitle == nil)
    }

    @Test("falls back to the source application when the title is empty")
    func fallsBackToSourceName() {
        let presentation = MusicPresentation(activity: Self.activity(title: "", source: "Music"))

        #expect(presentation.title == "Music")
    }

    @Test("falls back to a generic label when nothing is nameable")
    func fallsBackToGenericLabel() {
        let presentation = MusicPresentation(
            activity: Self.activity(title: "", artist: "", source: nil)
        )

        #expect(presentation.title == "Now Playing")
        #expect(presentation.subtitle == nil)
    }

    // MARK: - Transport

    @Test("offers previous, play/pause, and next in reading order")
    func transportControlOrder() {
        let controls = MusicPresentation(activity: Self.activity()).transportControls

        #expect(controls.map(\.command) == [.previousTrack, .playPause, .nextTrack])
    }

    /// The middle control is the one piece of transport that changes meaning
    /// with state, so its symbol and label must follow the state rather than be
    /// fixed at build time.
    @Test("the play/pause control reflects the current playback state")
    func playPauseFollowsState() {
        let playing = MusicPresentation(activity: Self.activity(state: .playing))
        let paused = MusicPresentation(activity: Self.activity(state: .paused))

        let playingControl = playing.transportControls[1]
        let pausedControl = paused.transportControls[1]

        #expect(playingControl.symbolName == "pause.fill")
        #expect(playingControl.accessibilityLabel == "Pause")
        #expect(pausedControl.symbolName == "play.fill")
        #expect(pausedControl.accessibilityLabel == "Play")
    }

    @Test("every transport control is labelled for VoiceOver")
    func transportControlsAreLabelled() {
        let controls = MusicPresentation(activity: Self.activity()).transportControls

        #expect(controls.allSatisfy { $0.accessibilityLabel.isEmpty == false })
        #expect(controls.allSatisfy { $0.symbolName.isEmpty == false })
    }

    @Test("tapping a control sends its command exactly once")
    func sendsCommandOnTap() {
        var sent: [MusicTransportCommand] = []
        let view = MusicExpandedView(
            activity: Self.activity(),
            onTransport: { sent.append($0) }
        )

        for control in view.presentation.transportControls {
            view.perform(control)
        }

        #expect(sent == [.previousTrack, .playPause, .nextTrack])
    }

    // MARK: - Compact presentation

    @Test("the compact slot uses the music glyph and announces the track")
    func compactSlotDescribesTheTrack() {
        let slot = musicCompactSlot(for: Self.activity())

        #expect(slot.symbolName == "music.note")
        #expect(slot.accessibilityLabel == "Windowlicker — Aphex Twin")
    }

    @Test("the compact slot announces the paused state")
    func compactSlotAnnouncesPaused() {
        let slot = musicCompactSlot(for: Self.activity(state: .paused))

        #expect(slot.accessibilityLabel == "Paused: Windowlicker — Aphex Twin")
    }

    // MARK: - The backend-independence rule

    /// The acceptance criterion for todo 41: the views read `MusicActivity` and
    /// nothing else, so neither backend's vocabulary can reach them.
    @Test("renders from any activity carrying now-playing, whatever produced it")
    func rendersRegardlessOfBackend() {
        let fromScriptingBridgeShapedData = Self.activity(source: "Spotify")
        let fromMediaRemoteShapedData = Self.activity(source: nil)

        #expect(MusicPresentation(activity: fromScriptingBridgeShapedData).title == "Windowlicker")
        #expect(MusicPresentation(activity: fromMediaRemoteShapedData).title == "Windowlicker")
        #expect(
            MusicPresentation(activity: fromScriptingBridgeShapedData).transportControls.count
                == MusicPresentation(activity: fromMediaRemoteShapedData).transportControls.count
        )
    }

    // MARK: - Geometry

    @Test("the expanded music view fits the allocated panel")
    func expandedViewFitsThePanel() {
        let size = musicExpandedSize()

        #expect(size.width <= PanelMetrics.default.maximumExpandedSize.width)
        #expect(size.height <= PanelMetrics.default.maximumExpandedSize.height)
        #expect(size.height > 0)
    }
}
