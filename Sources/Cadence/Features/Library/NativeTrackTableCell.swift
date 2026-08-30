import AppKit
import QuartzCore

typealias NativeTrackArtworkLoader = @MainActor @Sendable (
    UUID,
    ArtworkAssetVariant
) async -> ArtworkAsset?

enum NativeTrackTableAction: Equatable, Sendable {
    case select
    case play
    case favorite
    case artist
    case album
}

enum NativeTrackTableChromeTone: Equatable, Sendable {
    case clear
    case selection
    case hover
    case primary
    case secondary
    case tertiary
}

struct NativeTrackTableChromePresentation: Equatable, Sendable {
    let fill: NativeTrackTableChromeTone
    let outline: NativeTrackTableChromeTone
    let favorite: NativeTrackTableChromeTone
    let action: NativeTrackTableChromeTone

    static func resolve(
        isSelected: Bool,
        isFocused _: Bool,
        isHovered: Bool,
        isLiveScrolling _: Bool,
        isFavorite: Bool
    ) -> NativeTrackTableChromePresentation {
        NativeTrackTableChromePresentation(
            fill: isSelected
                ? .selection
                : isHovered ? .hover : .clear,
            outline: .clear,
            favorite: isFavorite ? .primary : .secondary,
            action: isHovered ? .primary : .tertiary
        )
    }
}

@MainActor
private final class NativeTrackMetadataControl: NSTextField {
    var hoverChanged: (() -> Void)?
    private(set) var isPointerHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool {
        isEnabled
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [
                .activeInActiveApp,
                .inVisibleRect,
                .mouseEnteredAndExited,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
        setPointerHovered(true)
    }

    override func mouseExited(with _: NSEvent) {
        setPointerHovered(false)
    }

    override func mouseDown(with _: NSEvent) {
        guard isEnabled else {
            return
        }
        window?.makeFirstResponder(self)
        sendConfiguredAction()
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 36, 49:
            sendConfiguredAction()
        default:
            super.keyDown(with: event)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
    }

    private func sendConfiguredAction() {
        guard let action else {
            return
        }
        NSApp.sendAction(action, to: target, from: self)
    }

    func setPointerHovered(_ isHovered: Bool) {
        guard isPointerHovered != isHovered else {
            return
        }
        isPointerHovered = isHovered
        hoverChanged?()
    }

    func resetPointerHover() {
        isPointerHovered = false
    }
}

@MainActor
// One reusable AppKit cell owns a stable layer and control hierarchy for the hot scroll path.
// swiftlint:disable:next type_body_length
final class NativeTrackTableCell: NSTableCellView {
    private static let emptyHeartImage = NSImage(
        systemSymbolName: "heart",
        accessibilityDescription: nil
    )
    private static let filledHeartImage = NSImage(
        systemSymbolName: "heart.fill",
        accessibilityDescription: nil
    )
    private static let playImage = NSImage(
        systemSymbolName: "play.fill",
        accessibilityDescription: nil
    )
    private let probe: TrackTableWorkProbe?
    private let selectionLayer = CALayer()
    private let artworkLayer = CALayer()
    private let artworkOverlayLayer = CALayer()
    private let favoriteButton = NSButton()
    private let artworkButton = NSButton()
    private let playbackIndicator = NativePlaybackIndicatorView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistButton = NativeTrackMetadataControl()
    private let explicitLabel = NSTextField(labelWithString: "E")
    private let albumButton = NativeTrackMetadataControl()
    private let yearLabel = NSTextField(labelWithString: "")
    private let durationLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private var trackingArea: NSTrackingArea?
    private var projection: TrackRowDisplayProjection?
    private var columns: [TrackTableColumn] = []
    private var widths = TrackTableColumnPolicy.defaultWidths
    private var isSelected = false
    private var isFocused = false
    private var isLiveScrolling = false
    private var reduceMotion = false
    private var showsArtwork = true
    private var isHovered = false
    private var artworkTask: Task<Void, Never>?
    private var artworkGeneration: UInt64 = 0
    private var artworkRequest: ProductionArtworkRequest?
    private var hasConfiguredContent = false

    var onAction: ((UUID, NativeTrackTableAction) -> Void)?
    var onActionsMenu: ((UUID, NSButton) -> Void)?
    var onContextMenu: ((UUID, NSEvent) -> NSMenu?)?
    var artworkLoader: NativeTrackArtworkLoader?

    private(set) var representedTrackID: UUID?
    private(set) var publishedArtworkRequest: ProductionArtworkRequest?
    private(set) var publishedArtworkContentsRect = CGRect(
        x: 0,
        y: 0,
        width: 1,
        height: 1
    )

    init(
        frame frameRect: NSRect = .zero,
        probe: TrackTableWorkProbe? = nil
    ) {
        self.probe = probe
        super.init(frame: frameRect)
        identifier = TrackTableCore.Coordinator.cellIdentifier
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.masksToBounds = false
        selectionLayer.cornerRadius = CadenceTheme.radiusControl
        selectionLayer.actions = Self.disabledLayerActions
        artworkLayer.cornerRadius = CadenceTheme.radiusControl
        artworkLayer.masksToBounds = true
        artworkLayer.actions = Self.disabledLayerActions
        artworkOverlayLayer.cornerRadius = CadenceTheme.radiusControl
        artworkOverlayLayer.actions = Self.disabledLayerActions
        layer?.addSublayer(selectionLayer)
        layer?.addSublayer(artworkLayer)
        layer?.addSublayer(artworkOverlayLayer)
        configureSubviews()
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
        probe?.recordNativeCellCreation()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    isolated deinit {
        artworkTask?.cancel()
    }

    var renderHierarchyIdentity: [ObjectIdentifier] {
        [
            ObjectIdentifier(selectionLayer),
            ObjectIdentifier(artworkLayer),
            ObjectIdentifier(artworkOverlayLayer),
        ] + subviews.map(ObjectIdentifier.init)
    }

    func configure(
        _ content: NativeTrackTableContent,
        columns: [TrackTableColumn],
        widths: TrackTableResolvedWidths,
        isSelected: Bool,
        isFocused: Bool,
        isLiveScrolling: Bool,
        reduceMotion: Bool = false,
        showsArtwork: Bool = true,
        artworkLoader: NativeTrackArtworkLoader? = nil
    ) {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            probe?.recordNativeCellConfiguration(
                durationNanoseconds:
                DispatchTime.now().uptimeNanoseconds - started
            )
        }
        let nextProjection: TrackRowDisplayProjection? = switch content {
        case .placeholder:
            nil
        case let .track(projection):
            projection
        }
        let contentChanged = !hasConfiguredContent
            || projection != nextProjection
        let layoutChanged = !hasConfiguredContent
            || self.columns != columns
            || self.widths != widths
            || self.showsArtwork != showsArtwork
        let chromeChanged = !hasConfiguredContent
            || self.isSelected != isSelected
            || self.isFocused != isFocused
            || self.isLiveScrolling != isLiveScrolling
            || self.reduceMotion != reduceMotion
            || contentChanged
        let identityChanged = representedTrackID != nextProjection?.id
        if representedTrackID != nil, identityChanged {
            probe?.recordNativeTrackIdentityChange()
        }
        if identityChanged {
            resetPointerHover()
        }
        self.columns = columns
        self.widths = widths
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.isLiveScrolling = isLiveScrolling
        self.reduceMotion = reduceMotion
        self.showsArtwork = showsArtwork
        if let artworkLoader {
            self.artworkLoader = artworkLoader
        }
        representedTrackID = nextProjection?.id
        projection = nextProjection
        hasConfiguredContent = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if contentChanged {
            probe?.recordNativeContentApplication()
            applyContent()
        }
        if contentChanged || layoutChanged {
            updateArtwork(
                request: showsArtwork ? nextProjection?.artworkRequest : nil
            )
        }
        if chromeChanged {
            updateChrome()
        }
        if contentChanged || layoutChanged {
            probe?.recordNativeLayoutInvalidation()
            needsLayout = true
        }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutLayersAndSubviews()
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .activeInActiveApp,
            .inVisibleRect,
            .mouseEnteredAndExited,
        ]
        let area = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with _: NSEvent) {
        updatePointerHover(isHovered: true)
    }

    override func mouseExited(with _: NSEvent) {
        updatePointerHover(isHovered: false)
    }

    func updatePointerHover(isHovered: Bool) {
        guard self.isHovered != isHovered else {
            return
        }
        self.isHovered = isHovered
        updateChrome()
    }

    func resetPointerHover() {
        let changed = isHovered
            || artistButton.isPointerHovered
            || albumButton.isPointerHovered
        isHovered = false
        artistButton.resetPointerHover()
        albumButton.resetPointerHover()
        guard changed, hasConfiguredContent else {
            return
        }
        updateChrome()
    }

    func reconcilePointerHover(at windowPoint: NSPoint) {
        guard window != nil else {
            resetPointerHover()
            return
        }
        let localPoint = convert(windowPoint, from: nil)
        updatePointerHover(
            isHovered: bounds.contains(localPoint)
                && visibleRect.contains(localPoint)
        )
    }

    override func mouseDown(with event: NSEvent) {
        performAction(.select)
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let representedTrackID else {
            return nil
        }
        return onContextMenu?(representedTrackID, event)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            hasConfiguredContent = false
            cancelArtworkLoad(resetRequest: true)
            playbackIndicator.setPlaying(false, reduceMotion: reduceMotion)
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    private func configureSubviews() {
        configureButton(favoriteButton, action: #selector(favoritePressed))
        configureButton(artworkButton, action: #selector(playPressed))
        configureMetadataControls()
        configureButton(actionButton, action: #selector(actionsPressed))

        favoriteButton.imagePosition = .imageOnly
        favoriteButton.contentTintColor = .secondaryLabelColor
        artworkButton.imagePosition = .imageOnly
        artworkButton.contentTintColor = .white
        actionButton.imagePosition = .imageOnly
        actionButton.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: String(localized: "Track Actions")
        )
        actionButton.toolTip = String(localized: "Track Actions")

        configureLabel(titleLabel, font: .systemFont(ofSize: 13))
        configureLabel(
            explicitLabel,
            font: .systemFont(ofSize: 9, weight: .bold),
            alignment: .center
        )
        configureLabel(yearLabel, alignment: .right)
        configureLabel(durationLabel, alignment: .right)
        durationLabel.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )

        for view in [
            favoriteButton,
            artworkButton,
            playbackIndicator,
            titleLabel,
            artistButton,
            explicitLabel,
            albumButton,
            yearLabel,
            durationLabel,
            actionButton,
        ] {
            addSubview(view)
        }
    }

    private func configureMetadataControls() {
        configureMetadataControl(
            artistButton,
            action: #selector(artistPressed)
        )
        configureMetadataControl(
            albumButton,
            action: #selector(albumPressed)
        )
        artistButton.hoverChanged = { [weak self] in
            self?.updateMetadataLinkTones()
        }
        albumButton.hoverChanged = { [weak self] in
            self?.updateMetadataLinkTones()
        }
    }

    private func configureButton(
        _ button: NSButton,
        action: Selector
    ) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.lineBreakMode = .byTruncatingTail
        button.focusRingType = .none
        if let buttonCell = button.cell as? NSButtonCell {
            buttonCell.highlightsBy = []
            buttonCell.showsStateBy = []
        }
    }

    private func configureMetadataControl(
        _ control: NativeTrackMetadataControl,
        action: Selector
    ) {
        control.target = self
        control.action = action
        control.font = .systemFont(ofSize: NSFont.systemFontSize)
        control.alignment = .left
        control.textColor = .secondaryLabelColor
        control.lineBreakMode = .byTruncatingTail
        control.maximumNumberOfLines = 1
        control.isSelectable = false
        control.isEditable = false
        control.drawsBackground = false
        control.isBezeled = false
        control.focusRingType = .none
        control.setAccessibilityRole(.link)
    }

    private func configureLabel(
        _ label: NSTextField,
        font: NSFont = .systemFont(ofSize: NSFont.systemFontSize),
        alignment: NSTextAlignment = .left
    ) {
        label.font = font
        label.alignment = alignment
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.isSelectable = false
        label.isEditable = false
        label.drawsBackground = false
        label.isBezeled = false
    }

    private func applyContent() {
        guard let projection else {
            titleLabel.stringValue = String(localized: "Loading…")
            titleLabel.toolTip = nil
            artistButton.stringValue = ""
            albumButton.stringValue = ""
            yearLabel.stringValue = ""
            durationLabel.stringValue = ""
            representedTrackID = nil
            setAccessibilityLabel(String(localized: "Loading track"))
            for view in interactiveSubviews {
                view.isEnabled = false
            }
            explicitLabel.isHidden = true
            playbackIndicator.isHidden = true
            playbackIndicator.setPlaying(false, reduceMotion: reduceMotion)
            return
        }

        titleLabel.stringValue = projection.title
        titleLabel.toolTip = projection.title
        titleLabel.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: projection.isCurrentTrack ? .semibold : .regular
        )
        artistButton.stringValue = projection.artist
        artistButton.toolTip = projection.artist
        artistButton.isEnabled = projection.artistID != nil
        albumButton.stringValue = projection.album
        albumButton.toolTip = projection.album
        albumButton.isEnabled = projection.albumID != nil
        yearLabel.stringValue = projection.year
        durationLabel.stringValue = projection.duration
        explicitLabel.isHidden = !projection.isExplicit
        favoriteButton.isEnabled = true
        artworkButton.isEnabled = true
        actionButton.isEnabled = true
        setAccessibilityLabel(projection.accessibilityLabel)
        setAccessibilitySelected(isSelected)
        favoriteButton.setAccessibilityLabel(
            projection.isFavorite
                ? String(localized: "Remove from Favorites")
                : String(localized: "Add to Favorites")
        )
        artworkButton.toolTip = String(
            localized: "Play \(projection.title)"
        )
        updateMetadataLinkTones()
    }

    private func updateChrome() {
        let disablesAnimation = isLiveScrolling || reduceMotion
        let presentation = NativeTrackTableChromePresentation.resolve(
            isSelected: isSelected,
            isFocused: isFocused,
            isHovered: isHovered,
            isLiveScrolling: isLiveScrolling,
            isFavorite: projection?.isFavorite == true
        )
        CATransaction.begin()
        CATransaction.setDisableActions(disablesAnimation)
        selectionLayer.backgroundColor = color(
            for: presentation.fill
        ).cgColor
        selectionLayer.borderColor = color(
            for: presentation.outline
        ).withAlphaComponent(0.62).cgColor
        selectionLayer.borderWidth = presentation.outline == .clear ? 0 : 1
        artworkLayer.backgroundColor = NSColor.controlBackgroundColor.cgColor
        artworkOverlayLayer.backgroundColor = projection?.isCurrentTrack == true
            ? NSColor.black.withAlphaComponent(0.34).cgColor
            : NSColor.clear.cgColor
        CATransaction.commit()
        setAccessibilitySelected(isSelected)

        guard projection != nil else {
            favoriteButton.isHidden = true
            actionButton.contentTintColor = .tertiaryLabelColor
            return
        }
        updateFavoriteChrome()
        actionButton.contentTintColor = color(for: presentation.action)
        updateArtworkPlaybackChrome()
        updateMetadataLinkTones()
    }

    private func updateFavoriteChrome() {
        guard let projection else {
            return
        }
        switch NativeFavoriteVisibility.resolve(
            isFavorite: projection.isFavorite,
            isHovered: isHovered,
            isLiveScrolling: isLiveScrolling
        ) {
        case .hidden:
            favoriteButton.image = Self.emptyHeartImage
            favoriteButton.contentTintColor = .secondaryLabelColor
            favoriteButton.isHidden = true
        case .emptySecondary:
            favoriteButton.image = Self.emptyHeartImage
            favoriteButton.contentTintColor = .secondaryLabelColor
            favoriteButton.isHidden = false
        case .filledPrimary:
            favoriteButton.image = Self.filledHeartImage
            favoriteButton.contentTintColor = CadenceTheme.nativePrimaryAccent
            favoriteButton.isHidden = false
        }
    }

    private func updateArtworkPlaybackChrome() {
        guard let projection else {
            return
        }
        let showsPlaybackIndicator = projection.isCurrentTrack
            && projection.isPlaying
        artworkButton.image = showsPlaybackIndicator ? nil : Self.playImage
        artworkButton.isHidden = !isHovered && !projection.isCurrentTrack
        playbackIndicator.isHidden = !showsPlaybackIndicator
        playbackIndicator.setPlaying(
            showsPlaybackIndicator,
            reduceMotion: reduceMotion
        )
    }

    private func updateMetadataLinkTones() {
        artistButton.textColor = metadataTone(for: artistButton)
        albumButton.textColor = metadataTone(for: albumButton)
    }

    private func metadataTone(
        for button: NativeTrackMetadataControl
    ) -> NSColor {
        let isFocused = window?.firstResponder === button
        return button.isEnabled
            ? button.isPointerHovered || isFocused
            ? .labelColor
            : .secondaryLabelColor
            : .tertiaryLabelColor
    }

    private func color(
        for tone: NativeTrackTableChromeTone
    ) -> NSColor {
        switch tone {
        case .clear:
            .clear
        case .selection:
            CadenceTheme.nativeSelectionFill
        case .hover:
            CadenceTheme.nativeHoverFill
        case .primary:
            CadenceTheme.nativePrimaryAccent
        case .secondary:
            .secondaryLabelColor
        case .tertiary:
            .tertiaryLabelColor
        }
    }

    private func updateArtwork(request: ProductionArtworkRequest?) {
        guard artworkRequest != request else {
            return
        }
        artworkRequest = request
        artworkGeneration &+= 1
        let generation = artworkGeneration
        artworkTask?.cancel()
        artworkTask = nil
        publishedArtworkRequest = nil
        publishedArtworkContentsRect = Self.unitContentsRect
        artworkLayer.contents = nil
        artworkLayer.contentsRect = Self.unitContentsRect
        guard
            let request,
            let artworkID = request.artworkID,
            let artworkLoader
        else {
            return
        }
        artworkTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let asset = await artworkLoader(artworkID, request.variant)
            guard !Task.isCancelled, let asset else {
                return
            }
            let image = await ArtworkImageCache.shared.image(for: asset)
            guard
                !Task.isCancelled,
                let image,
                artworkGeneration == generation,
                artworkRequest == request
            else {
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            artworkLayer.contents = image
            artworkLayer.contentsGravity = .resizeAspectFill
            let contentsRect = Self.artworkContentsRect(
                asset: asset,
                image: image
            )
            artworkLayer.contentsRect = contentsRect
            artworkLayer.contentsScale = window?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor
                ?? 2
            publishedArtworkRequest = request
            publishedArtworkContentsRect = contentsRect
            CATransaction.commit()
        }
    }

    private func cancelArtworkLoad(resetRequest: Bool) {
        artworkGeneration &+= 1
        artworkTask?.cancel()
        artworkTask = nil
        publishedArtworkRequest = nil
        publishedArtworkContentsRect = Self.unitContentsRect
        artworkLayer.contents = nil
        artworkLayer.contentsRect = Self.unitContentsRect
        if resetRequest {
            artworkRequest = nil
        }
    }

    private static func artworkContentsRect(
        asset: ArtworkAsset,
        image: CGImage
    ) -> CGRect {
        let pixelWidth = CGFloat(image.width)
        let pixelHeight = CGFloat(image.height)
        guard pixelWidth > 0, pixelHeight > 0 else {
            return unitContentsRect
        }

        let baseRect: CGRect
        if pixelWidth > pixelHeight {
            let width = pixelHeight / pixelWidth
            baseRect = CGRect(
                x: (1 - width) / 2,
                y: 0,
                width: width,
                height: 1
            )
        } else if pixelHeight > pixelWidth {
            let height = pixelWidth / pixelHeight
            baseRect = CGRect(
                x: 0,
                y: (1 - height) / 2,
                width: 1,
                height: height
            )
        } else {
            baseRect = unitContentsRect
        }

        let zoom = max(asset.scale, 1)
        let size = CGSize(
            width: baseRect.width / zoom,
            height: baseRect.height / zoom
        )
        var origin = CGPoint(
            x: baseRect.midX - size.width / 2,
            y: baseRect.midY - size.height / 2
        )
        origin.x -= asset.normalizedOffset.width * size.width
        origin.y += asset.normalizedOffset.height * size.height
        origin.x = min(
            max(origin.x, baseRect.minX),
            baseRect.maxX - size.width
        )
        origin.y = min(
            max(origin.y, baseRect.minY),
            baseRect.maxY - size.height
        )
        return CGRect(origin: origin, size: size)
    }

    private static let unitContentsRect = CGRect(
        x: 0,
        y: 0,
        width: 1,
        height: 1
    )

    private var interactiveSubviews: [NSControl] {
        [
            favoriteButton,
            artworkButton,
            artistButton,
            albumButton,
            actionButton,
        ]
    }

    private func layoutLayersAndSubviews() {
        let inset = TrackTableColumnPolicy.horizontalInset
        let spacing = TrackTableColumnPolicy.columnSpacing
        let controlSize = TrackTableColumnPolicy.favoriteControlWidth
        let rowHeight = bounds.height
        let geometry = NativeTrackRowGeometry(rowHeight: rowHeight)
        selectionLayer.frame = bounds.insetBy(
            dx: TrackTableColumnPolicy.selectionHorizontalInset,
            dy: 3
        )

        var x = inset
        favoriteButton.frame = NSRect(
            x: x,
            y: (rowHeight - controlSize) / 2,
            width: controlSize,
            height: controlSize
        )
        x += controlSize + spacing

        let horizontalGeometry = NativeTrackRowHorizontalGeometry(
            rowHeight: rowHeight,
            leadingX: x,
            showsArtwork: showsArtwork
        )
        let artworkFrame = horizontalGeometry.artworkFrame ?? .zero
        artworkLayer.frame = artworkFrame
        artworkOverlayLayer.frame = artworkFrame
        artworkButton.frame = artworkFrame
        playbackIndicator.frame = artworkFrame
        artworkLayer.isHidden = !showsArtwork
        artworkOverlayLayer.isHidden = !showsArtwork
        artworkButton.isHidden = !showsArtwork
        playbackIndicator.isHidden = !showsArtwork
        x = horizontalGeometry.songOriginX

        let songEnd = inset + CGFloat(widths.song)
        let songTextWidth = max(songEnd - x, 1)
        layoutSongMetadata(
            originX: x,
            width: songTextWidth,
            geometry: geometry
        )

        x = songEnd + spacing
        for column in columns {
            let width = CGFloat(widths[column])
            switch column {
            case .album:
                let linkWidth = metadataControlWidth(
                    albumButton,
                    maximum: width
                )
                albumButton.frame = NSRect(
                    x: x,
                    y: geometry.singleLineFrame.minY,
                    width: linkWidth,
                    height: geometry.singleLineFrame.height
                )
            case .year:
                yearLabel.frame = NSRect(
                    x: x,
                    y: geometry.singleLineFrame.minY,
                    width: width,
                    height: geometry.singleLineFrame.height
                )
            case .time:
                durationLabel.frame = NSRect(
                    x: x,
                    y: geometry.singleLineFrame.minY,
                    width: width,
                    height: geometry.singleLineFrame.height
                )
            }
            x += width + spacing
        }
        albumButton.isHidden = !columns.contains(.album)
        yearLabel.isHidden = !columns.contains(.year)
        durationLabel.isHidden = !columns.contains(.time)
        actionButton.frame = NSRect(
            x: max(
                bounds.maxX - inset - TrackTableColumnPolicy.actionWidth,
                x
            ),
            y: (rowHeight - TrackTableColumnPolicy.actionWidth) / 2,
            width: TrackTableColumnPolicy.actionWidth,
            height: TrackTableColumnPolicy.actionWidth
        )
    }

    private func layoutSongMetadata(
        originX: CGFloat,
        width: CGFloat,
        geometry: NativeTrackRowGeometry
    ) {
        let badgeGap: CGFloat = 7
        let badgeHeight: CGFloat = 16
        let explicitReserve = explicitLabel.isHidden
            ? 0
            : badgeGap + 16
        let titleWidth = max(width - explicitReserve, 1)
        titleLabel.frame = NSRect(
            x: originX,
            y: geometry.titleFrame.minY,
            width: titleWidth,
            height: geometry.titleFrame.height
        )
        explicitLabel.frame = NSRect(
            x: titleLabel.frame.maxX + badgeGap,
            y: geometry.titleFrame.minY + 1,
            width: 16,
            height: badgeHeight
        )
        artistButton.frame = NSRect(
            x: originX,
            y: geometry.artistFrame.minY,
            width: metadataControlWidth(
                artistButton,
                maximum: width
            ),
            height: geometry.artistFrame.height
        )
    }

    private func metadataControlWidth(
        _ control: NSTextField,
        maximum: CGFloat
    ) -> CGFloat {
        let renderedWidth = ceil(
            control.cell?.cellSize.width
                ?? control.intrinsicContentSize.width
        )
        return min(max(renderedWidth, 1), maximum)
    }

    func performAction(_ action: NativeTrackTableAction) {
        guard let representedTrackID else {
            return
        }
        onAction?(representedTrackID, action)
    }

    @objc private func favoritePressed() {
        performAction(.favorite)
    }

    @objc private func playPressed() {
        performAction(.play)
    }

    @objc private func artistPressed() {
        performAction(.artist)
    }

    @objc private func albumPressed() {
        performAction(.album)
    }

    @objc private func actionsPressed() {
        guard let representedTrackID else {
            return
        }
        onActionsMenu?(representedTrackID, actionButton)
    }

    private static let disabledLayerActions: [String: any CAAction] = [
        "backgroundColor": NSNull(),
        "borderColor": NSNull(),
        "borderWidth": NSNull(),
        "bounds": NSNull(),
        "contents": NSNull(),
        "opacity": NSNull(),
        "position": NSNull(),
    ]
}
