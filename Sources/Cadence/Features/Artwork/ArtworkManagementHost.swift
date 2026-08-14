import SwiftUI
import UniformTypeIdentifiers

private struct ArtworkManagementModifier: ViewModifier {
    @Bindable var model: CadenceAppModel

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $model.isArtworkImporterPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false,
                onCompletion: handleImageImport
            )
            .sheet(item: $model.artworkCropDraft) { draft in
                ArtworkCropSheet(
                    draft: draft,
                    cancel: model.cancelArtworkCrop,
                    save: { scale, normalizedOffset in
                        model.finishArtworkCrop(
                            draft,
                            scale: scale,
                            normalizedOffset: normalizedOffset
                        )
                    }
                )
            }
            .alert(
                "Couldn’t Open Artwork",
                isPresented: Binding(
                    get: { model.artworkImportError != nil },
                    set: {
                        if !$0 {
                            model.dismissArtworkImportError()
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    model.dismissArtworkImportError()
                }
            } message: {
                Text(
                    ProductErrorMessage(
                        detail: model.artworkImportError
                            ?? String(localized: "The selected image could not be read."),
                        preservedState: String(localized: "The current artwork is unchanged."),
                        recoveryAction: String(localized: "Choose a different image.")
                    ).text
                )
            }
    }

    private func handleImageImport(
        _ result: Result<[URL], any Error>
    ) {
        Task { @MainActor in
            do {
                guard let url = try result.get().first else {
                    model.cancelArtworkImport()
                    return
                }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                let data = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(
                        contentsOf: url,
                        options: [.mappedIfSafe]
                    )
                    guard
                        !data.isEmpty,
                        MetadataReader().artworkPayload(data: data) != nil
                    else {
                        throw ArtworkImportError.invalidImage
                    }
                    return data
                }.value
                model.prepareArtworkCrop(data: data)
            } catch let error as CocoaError where error.code == .userCancelled {
                model.cancelArtworkImport()
            } catch {
                model.presentArtworkImportError(error.localizedDescription)
            }
        }
    }
}

extension View {
    func artworkManagement(model: CadenceAppModel) -> some View {
        modifier(ArtworkManagementModifier(model: model))
    }
}

private enum ArtworkImportError: LocalizedError, Sendable {
    case invalidImage

    var errorDescription: String? {
        "The selected file is empty or is not a readable image."
    }
}
