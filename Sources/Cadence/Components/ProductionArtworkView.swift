import Observation
import SwiftUI

struct ProductionArtworkRequest: Hashable, Sendable {
    let artworkID: UUID?
    let variant: ArtworkAssetVariant
}

typealias ProductionArtworkLoader = @MainActor @Sendable (
    UUID,
    ArtworkAssetVariant
) async -> ArtworkAsset?

@MainActor
@Observable
final class ProductionArtworkLoadState {
    private(set) var asset: ArtworkAsset?
    private(set) var requestStarts = 0
    private(set) var publications = 0
    private var generation: UInt64 = 0
    private var currentRequest: ProductionArtworkRequest?
    private var completedRequest: ProductionArtworkRequest?

    func asset(for request: ProductionArtworkRequest) -> ArtworkAsset? {
        currentRequest == request ? asset : nil
    }

    func hasCompleted(_ request: ProductionArtworkRequest) -> Bool {
        currentRequest == request && completedRequest == request
    }

    @discardableResult
    func begin(request: ProductionArtworkRequest) -> UInt64 {
        generation &+= 1
        currentRequest = request
        completedRequest = nil
        requestStarts += 1
        asset = nil
        return generation
    }

    @discardableResult
    func publish(
        _ asset: ArtworkAsset?,
        request: ProductionArtworkRequest,
        generation: UInt64
    ) -> Bool {
        guard
            currentRequest == request,
            self.generation == generation
        else {
            return false
        }
        self.asset = asset
        completedRequest = request
        publications += 1
        return true
    }
}

@MainActor
final class ProductionArtworkWorkProbe {
    private(set) var taskStarts = 0
    private(set) var publishedArtworkIDs: [UUID] = []

    func recordTaskStart() {
        taskStarts += 1
    }

    func recordPublication(artworkID: UUID) {
        publishedArtworkIDs.append(artworkID)
    }
}

struct ProductionArtworkView: View {
    @Bindable var model: CadenceAppModel
    let artworkID: UUID?
    let title: String
    let placeholder: ArtworkPlaceholder
    var variant: ArtworkAssetVariant = .thumbnail
    var cornerRadius: CGFloat = 8
    var showsBorder = true
    var onReady: (@MainActor @Sendable () -> Void)?
    var artworkLoader: ProductionArtworkLoader?
    var workProbe: ProductionArtworkWorkProbe?
    var sharedLoadState: ProductionArtworkLoadState?

    @State private var ownedLoadState = ProductionArtworkLoadState()

    var body: some View {
        let loadState = sharedLoadState ?? ownedLoadState
        let artwork = MediaArtworkView(
            source: loadState.asset(for: request)
                .map(ResolvedArtworkSource.custom)
                ?? .placeholder(placeholder),
            title: title,
            placeholder: placeholder,
            cornerRadius: cornerRadius,
            showsBorder: showsBorder
        )

        if let artworkID {
            artwork.task(id: request) {
                guard !loadState.hasCompleted(request) else {
                    onReady?()
                    return
                }
                workProbe?.recordTaskStart()
                let generation = loadState.begin(request: request)
                guard !Task.isCancelled else {
                    return
                }
                let asset = if let artworkLoader {
                    await artworkLoader(artworkID, variant)
                } else {
                    await model.playbackArtworkAsset(
                        id: artworkID,
                        variant: variant
                    )
                }
                guard !Task.isCancelled else {
                    return
                }
                guard loadState.publish(
                    asset,
                    request: request,
                    generation: generation
                ) else {
                    return
                }
                workProbe?.recordPublication(artworkID: artworkID)
                onReady?()
            }
        } else {
            artwork.onAppear {
                onReady?()
            }
        }
    }

    private var request: ProductionArtworkRequest {
        ProductionArtworkRequest(
            artworkID: artworkID,
            variant: variant
        )
    }
}
