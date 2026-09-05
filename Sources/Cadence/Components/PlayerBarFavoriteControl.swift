import SwiftUI

struct PlayerBarFavoriteControl: View {
    @Bindable var model: CadenceAppModel

    var body: some View {
        if region == .transport,
           let track = model.currentPlaybackTrack {
            FavoriteButton(
                itemID: track.id,
                isFavorite: model.currentProductionTrackIsFavorite,
                itemName: track.title,
                controlSize: 28
            ) { requestedValue in
                await model.setProductionPlaybackTrackFavorite(
                    id: track.id,
                    isFavorite: requestedValue
                )
            }
        }
    }

    private var region: PlayerBarFavoriteRegion {
        PlayerBarFavoriteRegion.resolve(
            hasPlaybackItem: model.hasCurrentPlaybackItem,
            isExternal: model.isCurrentPlaybackExternal
        )
    }
}
