import SwiftUI

struct CollectionsView: View {
    @Bindable var model: CadenceAppModel
    @AppStorage("collections.contentSection")
    private var sectionRawValue = CollectionContentSection.playlists.rawValue

    var body: some View {
        VStack(spacing: 0) {
            collectionNavigation
            content
        }
        .background(CadenceTheme.contentBackground)
    }

    private var collectionNavigation: some View {
        HStack {
            Picker("Collections", selection: sectionBinding) {
                ForEach(CollectionContentSection.allCases) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 560)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(CadenceTheme.secondarySurface)
        .overlay(alignment: .bottom) {
            CadenceSeparator()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .playlists:
            PlaylistsView(
                model: model,
                store: model.librarySession.store
            )
        case .smartCollections:
            SmartCollectionsView(model: model)
        case .tags:
            TagsView(model: model)
        }
    }

    private var section: CollectionContentSection {
        CollectionContentSection(rawValue: sectionRawValue) ?? .playlists
    }

    private var sectionBinding: Binding<CollectionContentSection> {
        Binding(
            get: { section },
            set: { sectionRawValue = $0.rawValue }
        )
    }
}
