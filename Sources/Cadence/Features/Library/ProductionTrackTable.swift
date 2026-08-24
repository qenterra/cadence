import SwiftUI

struct ProductionTrackTable: View {
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Bindable var model: CadenceAppModel
    let tracks: [LibraryTrackProjection]
    let contentVersion: TrackTableContentVersion?
    var context: TrackTableContext = .library
    var showsHeader = true
    var compact = false
    var playlistID: UUID?
    var queueSource: PlaybackQueueSource?
    var reorderAction: (([UUID]) -> Void)?
    var onReachEnd: (() async -> Void)?
    var virtualWindow: LibraryTrackWindow?
    var repositorySortAction: ((LibraryTrackSort) async -> Void)?
    var selection: Binding<Set<UUID>>?
    var defaultSortDescriptor: TrackTableSortDescriptor?
    var refreshAction: CadenceRefreshAction?

    @State private var localSelection: Set<UUID> = []
    @State private var usesDefaultSort = true
    @State private var projectionCache = TrackTableProjectionCache()

    @AppStorage("trackTable.visibleColumns")
    private var visibleColumnsRaw = TrackTableColumn.defaultRawValue
    @AppStorage("trackTable.columnDefaultsVersion")
    private var columnDefaultsVersion = 0
    @AppStorage("trackTable.sortField")
    private var sortFieldRaw = TrackTableSortField.song.rawValue
    @AppStorage("trackTable.sortDirection")
    private var sortDirectionRaw = TrackTableSortDirection.ascending.rawValue

    var body: some View {
        let snapshot = resolvedSnapshot
        GeometryReader { geometry in
            let availableWidth = max(geometry.size.width, 1)
            let useCompactLayout = compact
                || TrackTableColumnPolicy.mode(
                    availableWidth: availableWidth
                ) == .compact
            let columns = useCompactLayout ? [] : visibleColumns
            let contentWidth = TrackTableColumnPolicy.contentWidth(
                availableWidth: availableWidth,
                columns: columns
            )
            let resolvedWidths = TrackTableColumnPolicy.layout(
                availableWidth: contentWidth,
                columns: columns
            )

            VStack(spacing: 0) {
                if showsHeader {
                    header(
                        columns: columns,
                        widths: resolvedWidths
                    )
                    .transition(.opacity)
                }

                TrackTableCore(
                    model: model,
                    context: context,
                    snapshot: snapshot,
                    virtualWindow: virtualWindow,
                    columns: columns,
                    widths: resolvedWidths,
                    playlistID: playlistID,
                    queueSource: queueSource,
                    reorderAction: reorderAction,
                    onReachEnd: onReachEnd,
                    refreshAction: refreshAction,
                    currentTrackID: model.currentProductionTrackID,
                    isCurrentTrackPlaying:
                    model.isCurrentProductionTrackPlaying,
                    selection: selectedTrackIDs
                )
            }
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: CadenceTheme.motionReplace),
                value: useCompactLayout
            )
        }
        .task(id: repositorySort) {
            await repositorySortAction?(repositorySort)
        }
        .task {
            let migrated = TrackTableColumn.migrateDefaults(
                rawValue: visibleColumnsRaw,
                version: columnDefaultsVersion
            )
            visibleColumnsRaw = migrated.rawValue
            columnDefaultsVersion = migrated.version
        }
        .onChange(of: snapshot?.identity, initial: true) {
            guard let snapshot else {
                return
            }
            selectedTrackIDs.wrappedValue.formIntersection(
                Set(snapshot.orderedIDs)
            )
        }
        .onChange(of: context) {
            selectedTrackIDs.wrappedValue = []
            usesDefaultSort = true
        }
    }
}

private extension ProductionTrackTable {
    var visibleColumns: [TrackTableColumn] {
        TrackTableColumn.decode(visibleColumnsRaw)
    }

    var resolvedSnapshot: TrackTableProjectionSnapshot? {
        if virtualWindow != nil {
            precondition(
                contentVersion == nil,
                "Virtual track tables must not supply a materialized content version"
            )
            return nil
        }
        guard let contentVersion else {
            preconditionFailure(
                "Materialized track tables require a producer-owned content version"
            )
        }
        return projectionCache.resolve(
            rows: tracks,
            contentVersion: contentVersion,
            sortDescriptor: effectiveSortDescriptor,
            repositoryOrdered: repositorySortAction != nil
        )
    }

    var selectedTrackIDs: Binding<Set<UUID>> {
        selection ?? $localSelection
    }

    var repositorySort: LibraryTrackSort {
        let field: LibraryTrackSortField = switch effectiveSortDescriptor.field {
        case .song: .song
        case .album: .album
        case .year: .year
        case .time: .duration
        }
        return LibraryTrackSort(
            field: field,
            direction: effectiveSortDescriptor.direction == .ascending
                ? .ascending
                : .descending
        )
    }

    var sortDescriptor: TrackTableSortDescriptor {
        TrackTableSortDescriptor(
            field: TrackTableSortField(rawValue: sortFieldRaw) ?? .song,
            direction: TrackTableSortDirection(
                rawValue: sortDirectionRaw
            ) ?? .ascending
        )
    }

    var effectiveSortDescriptor: TrackTableSortDescriptor {
        if usesDefaultSort, let defaultSortDescriptor {
            return defaultSortDescriptor
        }
        return sortDescriptor
    }

    func header(
        columns: [TrackTableColumn],
        widths: TrackTableResolvedWidths
    ) -> some View {
        HStack(spacing: TrackTableColumnPolicy.columnSpacing) {
            headerCell(
                field: .song,
                resolvedWidth: widths.song
            )

            ForEach(columns) { column in
                headerCell(
                    field: sortField(for: column),
                    resolvedWidth: widths[column]
                )
            }

            Spacer(minLength: 0)

            columnMenu
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, TrackTableColumnPolicy.horizontalInset)
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)
        }
        .contextMenu {
            ForEach(TrackTableColumn.allCases) { column in
                Toggle(
                    column.title,
                    isOn: visibilityBinding(for: column)
                )
            }
        }
    }

    private var columnMenu: some View {
        Menu {
            Text("Columns")
            ForEach(TrackTableColumn.allCases) { column in
                Toggle(
                    column.title,
                    isOn: visibilityBinding(for: column)
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(
                    width: TrackTableColumnPolicy.actionWidth,
                    height: TrackTableColumnPolicy.actionWidth
                )
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .help("Choose Columns")
    }

    func headerCell(
        field: TrackTableSortField,
        resolvedWidth: Double
    ) -> some View {
        TrackTableHeaderCell(
            title: field.title,
            alignment: field == .song || field == .album
                ? .leading
                : .trailing,
            isSorted: effectiveSortDescriptor.field == field,
            direction: effectiveSortDescriptor.direction,
            resolvedWidth: resolvedWidth,
            sortAction: { activateSort(field) }
        )
    }

    func activateSort(_ field: TrackTableSortField) {
        let current = effectiveSortDescriptor
        usesDefaultSort = false
        var direction = current.direction
        if current.field == field {
            direction.toggle()
        } else {
            direction = .ascending
        }
        sortFieldRaw = field.rawValue
        sortDirectionRaw = direction.rawValue
    }

    func visibilityBinding(
        for column: TrackTableColumn
    ) -> Binding<Bool> {
        Binding(
            get: { visibleColumns.contains(column) },
            set: { isVisible in
                var columns = Set(visibleColumns)
                if isVisible {
                    columns.insert(column)
                } else {
                    columns.remove(column)
                }
                visibleColumnsRaw = TrackTableColumn.encode(columns)
            }
        )
    }

    func sortField(
        for column: TrackTableColumn
    ) -> TrackTableSortField {
        switch column {
        case .album: .album
        case .year: .year
        case .time: .time
        }
    }
}
