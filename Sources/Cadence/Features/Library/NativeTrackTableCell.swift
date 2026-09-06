import AppKit
import QenTerraMediaComponents

/// Keeps asynchronous artwork and work-probe ownership in Cadence; all rendering is shared.
@MainActor
final class NativeTrackTableCell: NSTableCellView {
    let presentationView = NativeMediaTableCell()
    private let probe: TrackTableWorkProbe?
    private var artworkTask: Task<Void, Never>?
    private var artworkRequest: ProductionArtworkRequest?
    var onAction: ((UUID, NativeTrackTableAction) -> Void)?
    var onActionsMenu: ((UUID, NSButton) -> Void)?
    var onContextMenu: ((UUID, NSEvent) -> NSMenu?)?
    var artworkLoader: NativeTrackArtworkLoader?
    private(set) var publishedArtworkRequest: ProductionArtworkRequest?

    var representedTrackID: UUID? {
        presentationView.representedItemID?.base as? UUID
    }

    var publishedArtworkContentsRect: CGRect {
        presentationView.publishedArtworkContentsRect
    }

    var renderHierarchyIdentity: [ObjectIdentifier] {
        [ObjectIdentifier(presentationView)] + presentationView.renderHierarchyIdentity
    }

    init(frame frameRect: NSRect = .zero, probe: TrackTableWorkProbe? = nil) {
        self.probe = probe
        super.init(frame: frameRect)
        identifier = TrackTableCore.Coordinator.cellIdentifier
        wantsLayer = true
        presentationView.frame = bounds
        presentationView.autoresizingMask = [.width, .height]
        addSubview(presentationView)
        setAccessibilityElement(false)
        probe?.recordNativeCellCreation()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    isolated deinit { artworkTask?.cancel() }

    func configure(
        _ content: NativeTrackTableContent,
        columns: [TrackTableColumn],
        widths: TrackTableResolvedWidths,
        isSelected: Bool,
        isFocused: Bool,
        isLiveScrolling: Bool,
        reduceMotion: Bool = false,
        showsArtwork: Bool = true,
        density: TrackTableDensity = .standard,
        textSize: InterfaceTextSize = .standard,
        artworkLoader: NativeTrackArtworkLoader? = nil
    ) {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            probe?.recordNativeCellConfiguration(
                durationNanoseconds: DispatchTime.now().uptimeNanoseconds - started
            )
        }
        if let artworkLoader {
            self.artworkLoader = artworkLoader
        }
        let environment = CadenceTrackTableAdapter.environment(for: self, density: density, reduceMotion: reduceMotion)
        let state = MediaTableCellState(
            isSelected: isSelected, isFocused: isFocused, isLiveScrolling: isLiveScrolling,
            showsArtwork: showsArtwork, density: environment.density,
            typography: CadenceTrackTableAdapter.typography(textSize), environment: environment,
            favoriteControlWidth: TrackTableColumnPolicy.favoriteControlWidth,
            usesPrimaryActionTint: true
        )
        let previousID = representedTrackID
        let update: MediaTableCellUpdate
        switch content {
        case .placeholder:
            cancelArtwork()
            update = presentationView.configurePlaceholder(
                label: String(localized: "Loading…"), accessibilityLabel: String(localized: "Loading track"),
                state: state, columns: CadenceTrackTableAdapter.columns(columns),
                widths: CadenceTrackTableAdapter.widths(widths)
            )
        case let .track(row):
            let request = showsArtwork ? row.artworkRequest : nil
            if artworkRequest != request || previousID != row.id {
                cancelArtwork()
            }
            artworkRequest = request
            update = presentationView.configure(
                presentation: CadenceTrackTableAdapter.presentation(for: row), state: state,
                columns: CadenceTrackTableAdapter.columns(columns), widths: CadenceTrackTableAdapter.widths(widths),
                requestArtwork: { [weak self] token in self?.loadArtwork(token: token, request: row.artworkRequest) },
                actions: actions(for: row)
            )
        }
        if previousID != nil, previousID != representedTrackID {
            probe?.recordNativeTrackIdentityChange()
        }
        if update.contentApplied {
            probe?.recordNativeContentApplication()
        }
        if update.layoutInvalidated {
            probe?.recordNativeLayoutInvalidation()
        }
    }

    private func actions(for row: TrackRowDisplayProjection) -> NativeMediaTableActions<UUID> {
        let select: @MainActor (UUID) -> Void = { [weak self] id in self?.onAction?(id, .select) }
        let play: @MainActor (UUID) -> Void = { [weak self] id in self?.onAction?(id, .play) }
        let favorite: @MainActor (UUID) -> Void = { [weak self] id in self?.onAction?(id, .favorite) }
        let artist: @MainActor (UUID) -> Void = { [weak self] id in
            self?.onAction?(id, .artist)
        }
        let album: @MainActor (UUID) -> Void = { [weak self] id in
            self?.onAction?(id, .album)
        }
        let menu: @MainActor (UUID, NSButton) -> Void = { [weak self] id, button in
            self?.onActionsMenu?(id, button)
        }
        let context: @MainActor (UUID, NSEvent) -> NSMenu? = { [weak self] id, event in
            self?.onContextMenu?(id, event)
        }
        var availableArtist: (@MainActor (UUID) -> Void)?
        var availableAlbum: (@MainActor (UUID) -> Void)?
        if row.artistID != nil {
            availableArtist = artist
        }
        if row.albumID != nil {
            availableAlbum = album
        }
        return NativeMediaTableActions<UUID>(
            select: select, play: play, favorite: favorite,
            creator: availableArtist, collection: availableAlbum,
            actionsMenu: menu, contextMenu: context
        )
    }

    override func layout() {
        super.layout()
        presentationView.frame = bounds
        presentationView.layoutSubtreeIfNeeded()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        presentationView.menu(for: event)
    }

    override func mouseEntered(with _: NSEvent) {
        updatePointerHover(isHovered: true)
    }

    override func mouseExited(with _: NSEvent) {
        updatePointerHover(isHovered: false)
    }

    func updatePointerHover(isHovered: Bool) {
        presentationView.setPointerHovered(isHovered)
    }

    func resetPointerHover() {
        presentationView.resetPointerHover()
    }

    func reconcilePointerHover(at point: NSPoint) {
        presentationView.reconcilePointerHover(at: point)
    }

    func performAction(_ action: NativeTrackTableAction) {
        presentationView.performAction(CadenceTrackTableAdapter.action(action))
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            cancelArtwork()
            presentationView.prepareForReuse()
        }
    }

    private func loadArtwork(token: MediaTableArtworkRequest<UUID>, request: ProductionArtworkRequest) {
        artworkTask?.cancel()
        publishedArtworkRequest = nil
        guard let id = request.artworkID, let artworkLoader else { return }
        artworkTask = Task { @MainActor [weak self] in
            let asset = await artworkLoader(id, request.variant)
            guard !Task.isCancelled, let asset else { return }
            let image = await ArtworkImageCache.shared.image(for: asset)
            guard !Task.isCancelled, let self, let image, artworkRequest == request else { return }
            if presentationView.publishArtwork(
                image, for: token, contentsRect: CadenceTrackTableAdapter.artworkContentsRect(asset: asset, image: image)
            ) {
                publishedArtworkRequest = request
            }
        }
    }

    private func cancelArtwork() {
        artworkTask?.cancel()
        artworkTask = nil
        artworkRequest = nil
        publishedArtworkRequest = nil
    }
}
