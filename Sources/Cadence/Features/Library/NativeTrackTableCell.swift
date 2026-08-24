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
    private static let waveformImage = NSImage(
        systemSymbolName: "waveform",
        accessibilityDescription: nil
    )
    private let probe: TrackTableWorkProbe?
    private let selectionLayer = CALayer()
    private let artworkLayer = CALayer()
    private let artworkOverlayLayer = CALayer()
    private let favoriteButton = NSButton()
    private let artworkButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistButton = NSButton()
    private let codecLabel = NSTextField(labelWithString: "")
    private let explicitLabel = NSTextField(labelWithString: "E")
    private let lyricsLabel = NSTextField(labelWithString: "LRC")
    private let albumButton = NSButton()
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
    private var isHovered = false
    private var artworkTask: Task<Void, Never>?
    private var artworkGeneration: UInt64 = 0
    private var artworkRequest: ProductionArtworkRequest?
    private var hasConfiguredContent = false

    var onAction: ((UUID, NativeTrackTableAction) -> Void)?
    var onActionsMenu: ((UUID, NSButton) -> Void)?
    var onContextMenu: ((UUID) -> NSMenu?)?
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
        let chromeChanged = !hasConfiguredContent
            || self.isSelected != isSelected
            || self.isFocused != isFocused
            || self.isLiveScrolling != isLiveScrolling
            || self.reduceMotion != reduceMotion
            || contentChanged
        if let representedTrackID,
           representedTrackID != nextProjection?.id {
            probe?.recordNativeTrackIdentityChange()
        }
        self.columns = columns
        self.widths = widths
        self.isSelected = isSelected
        self.isFocused = isFocused
        self.isLiveScrolling = isLiveScrolling
        self.reduceMotion = reduceMotion
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
            updateArtwork(request: nextProjection?.artworkRequest)
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
        isHovered = true
        updateChrome()
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
        updateChrome()
    }

    override func mouseDown(with event: NSEvent) {
        performAction(.select)
        super.mouseDown(with: event)
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        guard let representedTrackID else {
            return nil
        }
        return onContextMenu?(representedTrackID)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateChrome()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil {
            hasConfiguredContent = false
            cancelArtworkLoad(resetRequest: true)
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    private func configureSubviews() {
        configureButton(favoriteButton, action: #selector(favoritePressed))
        configureButton(artworkButton, action: #selector(playPressed))
        configureButton(artistButton, action: #selector(artistPressed))
        configureButton(albumButton, action: #selector(albumPressed))
        configureButton(actionButton, action: #selector(actionsPressed))

        favoriteButton.imagePosition = .imageOnly
        favoriteButton.contentTintColor = .secondaryLabelColor
        artworkButton.imagePosition = .imageOnly
        artworkButton.contentTintColor = .white
        artistButton.alignment = .left
        albumButton.alignment = .left
        actionButton.imagePosition = .imageOnly
        actionButton.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: String(localized: "Track Actions")
        )
        actionButton.toolTip = String(localized: "Track Actions")

        configureLabel(titleLabel, font: .systemFont(ofSize: 13))
        configureLabel(
            codecLabel,
            font: .systemFont(ofSize: 9, weight: .semibold)
        )
        configureLabel(
            explicitLabel,
            font: .systemFont(ofSize: 9, weight: .bold),
            alignment: .center
        )
        configureLabel(
            lyricsLabel,
            font: .systemFont(ofSize: 9, weight: .semibold),
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
            titleLabel,
            artistButton,
            codecLabel,
            explicitLabel,
            lyricsLabel,
            albumButton,
            yearLabel,
            durationLabel,
            actionButton,
        ] {
            addSubview(view)
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
            artistButton.title = ""
            albumButton.title = ""
            codecLabel.stringValue = ""
            yearLabel.stringValue = ""
            durationLabel.stringValue = ""
            representedTrackID = nil
            setAccessibilityLabel(String(localized: "Loading track"))
            for view in interactiveSubviews {
                view.isEnabled = false
            }
            explicitLabel.isHidden = true
            lyricsLabel.isHidden = true
            return
        }

        titleLabel.stringValue = projection.title
        titleLabel.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: projection.isCurrentTrack ? .semibold : .regular
        )
        artistButton.title = projection.artist
        artistButton.toolTip = projection.artist
        artistButton.isEnabled = projection.artistID != nil
        albumButton.title = projection.album
        albumButton.toolTip = projection.album
        albumButton.isEnabled = projection.albumID != nil
        codecLabel.stringValue = projection.codec
        yearLabel.stringValue = projection.year
        durationLabel.stringValue = projection.duration
        explicitLabel.isHidden = !projection.isExplicit
        lyricsLabel.isHidden = !projection.hasSynchronizedLyrics
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
    }

    private func updateChrome() {
        let disablesAnimation = isLiveScrolling || reduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(disablesAnimation)
        selectionLayer.backgroundColor = rowBackgroundColor.cgColor
        selectionLayer.borderColor = isSelected && isFocused
            ? NSColor.keyboardFocusIndicatorColor
            .withAlphaComponent(0.45).cgColor
            : NSColor.clear.cgColor
        selectionLayer.borderWidth = isSelected && isFocused ? 1 : 0
        artworkLayer.backgroundColor = NSColor.controlBackgroundColor.cgColor
        artworkOverlayLayer.backgroundColor = projection?.isCurrentTrack == true
            ? NSColor.black.withAlphaComponent(0.34).cgColor
            : NSColor.clear.cgColor
        CATransaction.commit()
        setAccessibilitySelected(isSelected)

        guard let projection else {
            favoriteButton.isHidden = true
            actionButton.contentTintColor = .tertiaryLabelColor
            return
        }
        favoriteButton.image = projection.isFavorite
            ? Self.filledHeartImage
            : Self.emptyHeartImage
        favoriteButton.contentTintColor = projection.isFavorite
            ? .controlAccentColor
            : .secondaryLabelColor
        favoriteButton.isHidden = !projection.isFavorite
            && !isHovered
            && !isSelected
            && !isFocused
        actionButton.contentTintColor = isHovered
            ? .labelColor
            : .tertiaryLabelColor
        artworkButton.image = projection.isCurrentTrack && projection.isPlaying
            ? Self.waveformImage
            : Self.playImage
        artworkButton.isHidden = !isHovered && !projection.isCurrentTrack
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

    private var rowBackgroundColor: NSColor {
        if isSelected {
            return NSColor.selectedContentBackgroundColor
                .withAlphaComponent(isFocused ? 0.18 : 0.11)
        }
        if isHovered, !isLiveScrolling {
            return NSColor.labelColor.withAlphaComponent(0.045)
        }
        return .clear
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
        let artworkSize: CGFloat = 40
        let contentY = (rowHeight - artworkSize) / 2
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

        artworkLayer.frame = NSRect(
            x: x,
            y: contentY,
            width: artworkSize,
            height: artworkSize
        )
        artworkOverlayLayer.frame = artworkLayer.frame
        artworkButton.frame = artworkLayer.frame
        x += artworkSize + TrackTableColumnPolicy.songContentSpacing

        let songEnd = inset + CGFloat(widths.song)
        let songTextWidth = max(songEnd - x, 1)
        layoutSongMetadata(
            originX: x,
            width: songTextWidth,
            rowHeight: rowHeight
        )

        x = songEnd + spacing
        for column in columns {
            let width = CGFloat(widths[column])
            switch column {
            case .album:
                albumButton.frame = NSRect(
                    x: x,
                    y: 0,
                    width: width,
                    height: rowHeight
                )
            case .year:
                yearLabel.frame = NSRect(
                    x: x,
                    y: 0,
                    width: width,
                    height: rowHeight
                )
            case .time:
                durationLabel.frame = NSRect(
                    x: x,
                    y: 0,
                    width: width,
                    height: rowHeight
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
        rowHeight: CGFloat
    ) {
        let badgeGap: CGFloat = 7
        let badgeHeight: CGFloat = 16
        let topY = rowHeight / 2 + 1
        let titleIdealWidth = min(
            ceil(titleLabel.intrinsicContentSize.width),
            max(width * 0.62, 40)
        )
        titleLabel.frame = NSRect(
            x: originX,
            y: topY,
            width: titleIdealWidth,
            height: 19
        )
        var badgeX = titleLabel.frame.maxX + badgeGap
        codecLabel.sizeToFit()
        let codecWidth = min(
            max(codecLabel.frame.width + 10, 26),
            max(width - titleIdealWidth - badgeGap, 0)
        )
        codecLabel.frame = NSRect(
            x: badgeX,
            y: topY + 1,
            width: codecWidth,
            height: badgeHeight
        )
        badgeX += codecWidth + badgeGap
        explicitLabel.frame = NSRect(
            x: badgeX,
            y: topY + 1,
            width: 16,
            height: badgeHeight
        )
        if !explicitLabel.isHidden {
            badgeX += 16 + badgeGap
        }
        lyricsLabel.frame = NSRect(
            x: badgeX,
            y: topY + 1,
            width: 30,
            height: badgeHeight
        )
        artistButton.frame = NSRect(
            x: originX,
            y: 5,
            width: width,
            height: 19
        )
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
