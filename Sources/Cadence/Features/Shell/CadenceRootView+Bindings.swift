import SwiftUI

enum TextEntryEscapeResolution: Equatable, Sendable {
    case cancelEntry
    case propagate
}

enum TextEntryEscapePolicy {
    static func resolve(
        isFocused: Bool,
        textIsEmpty: Bool
    ) -> TextEntryEscapeResolution {
        isFocused || !textIsEmpty ? .cancelEntry : .propagate
    }
}

extension CadenceRootView {
    var supportsSearch: Bool {
        true
    }

    var activeSearchQuery: String {
        model.librarySession.store.catalogSearchQuery
    }

    var searchHelp: String {
        "Search Library"
    }

    var shouldPresentProductionSearch: Bool {
        supportsSearch
            && (isSearchPresented
                || !SearchNormalizer.normalize(activeSearchQuery).isEmpty)
    }

    var activeSearchBinding: Binding<String> {
        Binding(
            get: { model.librarySession.store.catalogSearchQuery },
            set: { query in
                Task {
                    await model.librarySession.store.searchCatalog(query)
                }
            }
        )
    }

    func dismissSearch() {
        isSearchPresented = false
        model.librarySession.store.clearCatalogSearch()
    }

    var libraryDeletionPresented: Binding<Bool> {
        Binding(
            get: { model.pendingLibraryDeletion != nil },
            set: {
                if !$0 {
                    model.cancelLibraryDeletion()
                }
            }
        )
    }

    var libraryOperationErrorPresented: Binding<Bool> {
        Binding(
            get: { model.libraryOperationError != nil },
            set: {
                if !$0 {
                    model.dismissLibraryOperationError()
                }
            }
        )
    }

    var storeOperationFailurePresented: Binding<Bool> {
        Binding(
            get: { model.librarySession.store.operationFailure != nil },
            set: {
                if !$0 {
                    model.librarySession.store.dismissOperationFailure()
                }
            }
        )
    }

    var externalAudioErrorPresented: Binding<Bool> {
        Binding(
            get: { model.externalAudioOpenError != nil },
            set: {
                if !$0 {
                    model.externalAudioOpenError = nil
                }
            }
        )
    }

    var externalAudioNoticePresented: Binding<Bool> {
        Binding(
            get: { model.externalAudioNotice != nil },
            set: {
                if !$0 {
                    model.externalAudioNotice = nil
                }
            }
        )
    }
}

struct CadenceSearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(
                text: $text,
                isPresented: $isPresented,
                placement: .toolbar,
                prompt: Text(prompt)
            )
        } else {
            content
        }
    }
}
