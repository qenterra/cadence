import SwiftUI

struct CadenceModeInputCapture: View {
    @Bindable var model: CadenceAppModel
    @Bindable var session: CadenceModeSession
    let isEnabled: Bool

    var body: some View {
        RhythmKeyboardCapture(
            canActivateCadenceMode: isEnabled
                && model.hasCurrentPlaybackItem,
            isCadenceModeActive: { session.isActive },
            onKeyDown: { lane in
                handleKeyDown(lane)
            },
            onKeyUp: { lane in
                session.keyUp(lane: lane)
            },
            onExitCadenceMode: {
                session.deactivate()
            },
            onReleaseAllKeys: {
                session.releaseAllKeys()
            }
        )
        .task {
            CadenceModeGradientPrewarmer.prepare()
            session.setEnabled(isEnabled)
        }
        .onChange(of: isEnabled) { _, enabled in
            session.setEnabled(enabled)
        }
        .onChange(of: model.playbackWorkspace) { _, workspace in
            synchronizePresentation(with: workspace)
        }
        .onChange(of: model.currentPlaybackTrack?.id) { oldID, newID in
            handleTrackChange(from: oldID, to: newID)
        }
    }

    private func handleKeyDown(_ lane: RhythmLane) {
        let action = session.keyDown(
            lane: lane,
            canActivate: isEnabled && model.hasCurrentPlaybackItem
        )
        guard action == .requestPresentation else {
            return
        }
        guard model.presentNowPlaying() else {
            session.deactivate()
            return
        }
    }

    private func synchronizePresentation(with workspace: PlaybackWorkspace) {
        if workspace != .nowPlaying, session.isActive {
            session.deactivate()
        }
    }

    private func handleTrackChange(from oldID: UUID?, to newID: UUID?) {
        guard oldID != nil, newID != nil, oldID != newID else {
            if newID == nil {
                session.deactivate()
            }
            return
        }
        session.currentTrackDidChange()
    }
}
