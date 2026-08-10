import SwiftUI

struct LibraryView: View {
    @Bindable var model: CadenceAppModel
    @AppStorage("library.contentSection")
    private var sectionRawValue = LibraryContentSection.tracks.rawValue
    @AppStorage("library.viewMode")
    private var viewModeRawValue = LibraryViewMode.content.rawValue

    var body: some View {
        VStack(spacing: 0) {
            libraryNavigation

            content
        }
        .background(CadenceTheme.contentBackground)
    }

    private var libraryNavigation: some View {
        HStack(spacing: 12) {
            Picker("Library", selection: sectionBinding) {
                ForEach(LibraryContentSection.allCases) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 560)

            Spacer(minLength: 12)

            Button {
                viewModeRawValue = (
                    viewMode == .content
                        ? LibraryViewMode.columnBrowser
                        : .content
                ).rawValue
            } label: {
                Image(systemName: viewMode.symbolName)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(CadenceRowButtonStyle())
            .help(
                viewMode == .content
                    ? "Show Column Browser"
                    : "Show Library Sections"
            )
            .accessibilityLabel(viewMode.title)
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
        if viewMode == .columnBrowser {
            ProductionLibraryView(
                model: model,
                store: model.librarySession.store
            )
        } else {
            switch section {
            case .tracks:
                AllTracksView(
                    model: model,
                    store: model.librarySession.store
                )
            case .albums:
                AlbumsView(model: model)
            case .artists:
                ArtistsView(model: model)
            case .favorites:
                LibraryFavoritesView(
                    model: model,
                    store: model.librarySession.store
                )
            }
        }
    }

    private var section: LibraryContentSection {
        LibraryContentSection(rawValue: sectionRawValue) ?? .tracks
    }

    private var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRawValue) ?? .content
    }

    private var sectionBinding: Binding<LibraryContentSection> {
        Binding(
            get: { section },
            set: { newSection in
                sectionRawValue = newSection.rawValue
                viewModeRawValue = LibraryViewMode.content.rawValue
            }
        )
    }
}

struct LibraryColumnHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

struct LibraryColumnWidths {
    let artists: CGFloat
    let albums: CGFloat
    let tracks: CGFloat

    init(totalWidth: CGFloat) {
        let availableWidth = max(totalWidth - 2, 0)
        if availableWidth < 950 {
            artists = (availableWidth * 0.27).clamped(to: 190 ... 260)
            albums = (availableWidth * 0.31).clamped(to: 230 ... 300)
            tracks = max(availableWidth - artists - albums, 0)
            return
        }
        let proposedArtists = (availableWidth * 0.29).clamped(to: 260 ... 410)
        let proposedAlbums = (availableWidth * 0.32).clamped(to: 300 ... 460)
        let proposedTracks = availableWidth - proposedArtists - proposedAlbums

        if proposedTracks >= 390 {
            artists = proposedArtists
            albums = proposedAlbums
            tracks = proposedTracks
        } else {
            let deficit = 390 - proposedTracks
            let artistCapacity = proposedArtists - 260
            let albumCapacity = proposedAlbums - 300
            let totalCapacity = artistCapacity + albumCapacity
            let artistReduction = totalCapacity > 0
                ? deficit * (artistCapacity / totalCapacity)
                : 0
            let albumReduction = deficit - artistReduction

            artists = max(proposedArtists - artistReduction, 260)
            albums = max(proposedAlbums - albumReduction, 300)
            tracks = max(availableWidth - artists - albums, 390)
        }
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
