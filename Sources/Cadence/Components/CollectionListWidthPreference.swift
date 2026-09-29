import SwiftUI

enum CollectionListWidthPage: Sendable {
    case playlists
    case smartCollections
    case tags
}

@propertyWrapper
struct CollectionListWidthPreference: DynamicProperty {
    let page: CollectionListWidthPage

    @AppStorage(CadencePreferences.Keys.collectionListWidthMode)
    private var modeRawValue = CollectionListWidthMode.shared.rawValue
    @AppStorage(CadencePreferences.Keys.collectionListWidth)
    private var sharedWidth = 270.0
    @AppStorage(CadencePreferences.Keys.playlistListWidth)
    private var playlistWidth = 270.0
    @AppStorage(CadencePreferences.Keys.smartCollectionListWidth)
    private var smartCollectionWidth = 270.0
    @AppStorage(CadencePreferences.Keys.tagListWidth)
    private var tagWidth = 300.0

    var binding: Binding<Double> {
        if mode == .shared {
            return $sharedWidth
        }

        switch page {
        case .playlists:
            return $playlistWidth
        case .smartCollections:
            return $smartCollectionWidth
        case .tags:
            return $tagWidth
        }
    }

    var wrappedValue: Binding<Double> {
        binding
    }

    private var mode: CollectionListWidthMode {
        CollectionListWidthMode(rawValue: modeRawValue) ?? .shared
    }
}
