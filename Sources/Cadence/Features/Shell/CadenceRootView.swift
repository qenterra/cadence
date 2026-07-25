import SwiftUI

struct CadenceRootView: View {
    @Bindable var model: CadenceAppModel

    @FocusState private var isSearchFocused: Bool
    @State private var isSearchPresented = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                NavigationRail(
                    selection: navigationSelection,
                    suppressesSelection: model.isPlaybackWorkspacePresented
                )
                Divider()
                workspaceContent
            }

            Divider()
            PlayerBar(model: model)
        }
        .background(CadenceTheme.contentBackground)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.playbackWorkspace == .hidden {
                    searchButton

                    Menu {
                        Button("Import Folder", systemImage: "folder.badge.plus") {
                            model.requestNavigationDestination(.importFolder)
                        }

                        Divider()

                        Button("Settings", systemImage: "gearshape") {
                            model.requestNavigationDestination(.settings)
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                    .labelStyle(.iconOnly)
                    .menuIndicator(.hidden)
                    .help("More")
                }
            }
        }
        .lyricsDraftTransitionAlert(model: model)
    }

    private var navigationSelection: Binding<NavigationDestination> {
        Binding(
            get: { model.selectedDestination },
            set: model.requestNavigationDestination
        )
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch model.playbackWorkspace {
        case .nowPlaying:
            NowPlayingView(model: model)
        case .lyricsEditor:
            LyricsEditorView(model: model)
        case .hidden:
            destinationContent
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch model.selectedDestination {
        case .library:
            LibraryView(model: model)
        case .albums:
            AlbumsView(model: model)
        case .tags:
            TagsView(model: model)
        case .smartCollections:
            SmartCollectionsView(model: model)
        case let destination:
            PlaceholderDestinationView(destination: destination)
        }
    }

    private var searchButton: some View {
        Button {
            isSearchPresented.toggle()
        } label: {
            Image(
                systemName: activeSearchQuery.isEmpty
                    ? "magnifyingglass"
                    : "magnifyingglass.circle.fill"
            )
        }
        .help(model.selectedDestination == .albums ? "Search Albums" : "Search Library")
        .keyboardShortcut("f", modifiers: .command)
        .popover(isPresented: $isSearchPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                if model.selectedDestination == .albums {
                    TextField("Search Albums", text: $model.albumSearchQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFocused)
                } else {
                    TextField("Search Library", text: $model.searchQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFocused)

                    Picker("Scope", selection: $model.searchScope) {
                        ForEach(LibrarySearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(16)
            .frame(width: 280)
            .onAppear {
                isSearchFocused = true
            }
        }
    }

    private var activeSearchQuery: String {
        model.selectedDestination == .albums
            ? model.albumSearchQuery
            : model.searchQuery
    }
}

private struct PlaceholderDestinationView: View {
    let destination: NavigationDestination

    var body: some View {
        ContentUnavailableView {
            Label(destination.title, systemImage: destination.symbolName)
        } description: {
            Text("This destination will arrive after the Column Library foundation.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CadenceTheme.contentBackground)
    }
}
