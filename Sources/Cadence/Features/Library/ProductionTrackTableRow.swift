import SwiftUI

struct TrackTableResolvedWidths: Equatable, Sendable {
    let song: Double
    let album: Double
    let year: Double
    let time: Double

    subscript(column: TrackTableColumn) -> Double {
        switch column {
        case .album: album
        case .year: year
        case .time: time
        }
    }
}

enum TrackRowActionMenuMaterializationPolicy: Equatable, Sendable {
    case always
    case whenEngaged

    static let production: Self = .whenEngaged

    func materializesFullActions(
        isHovered: Bool,
        isSelected: Bool,
        isFocused: Bool,
        isKeyboardFocused: Bool = false,
        isAccessibilityFocused: Bool = false,
        isLiveScrolling: Bool = false
    ) -> Bool {
        switch self {
        case .always:
            true
        case .whenEngaged:
            isKeyboardFocused
                || isAccessibilityFocused
                || (isSelected && isFocused)
                || (isHovered && !isLiveScrolling)
        }
    }
}

enum TrackRowLiveScrollPresentation: Equatable, Sendable {
    case interactive
    case pointerScrolling

    static func resolve(
        isLiveScrolling: Bool,
        isSelected: Bool,
        isFocused: Bool,
        isControlFocused: Bool,
        isAccessibilityFocused: Bool,
        isAssistiveTechnologyEnabled: Bool
    ) -> Self {
        guard isLiveScrolling,
              !(isSelected && isFocused),
              !isControlFocused,
              !isAccessibilityFocused,
              !isAssistiveTechnologyEnabled else {
            return .interactive
        }
        return .pointerScrolling
    }
}

struct ProductionTrackTableRow: View {
    @Bindable var model: CadenceAppModel
    let track: LibraryTrackProjection
    let queueIDProvider: TrackTableQueueIDProvider
    let columns: [TrackTableColumn]
    let widths: TrackTableResolvedWidths
    let playlistID: UUID?
    let queueSource: PlaybackQueueSource?
    let reorderAction: (([UUID]) -> Void)?
    let resolveDraggedTrackIDs: (Set<UUID>) -> Set<UUID>
    let actionTrackIDs: [UUID]
    let isSelected: Bool
    let isFocused: Bool
    let artworkLoader: ProductionArtworkLoader?
    let artworkWorkProbe: ProductionArtworkWorkProbe?
    let select: () -> Void
    var interactionState: TrackTableInteractionState?
    var workProbe: TrackTableWorkProbe?
    var actionMenuMaterializationPolicy =
        TrackRowActionMenuMaterializationPolicy.production

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilitySwitchControlEnabled)
    private var switchControlEnabled
    @Environment(\.accessibilityVoiceOverEnabled)
    private var voiceOverEnabled
    @FocusState private var isFavoriteFocused: Bool
    @FocusState private var isActionControlFocused: Bool
    @FocusState var isContentControlFocused: Bool
    @AccessibilityFocusState private var isActionControlAccessibilityFocused: Bool
    @State private var isHovered = false
    @State private var artworkLoadState = ProductionArtworkLoadState()

    var body: some View {
        Group {
            switch liveScrollPresentation {
            case .interactive:
                interactiveRow
            case .pointerScrolling:
                lightweightPointerScrollRow
            }
        }
        .transaction { transaction in
            guard isLiveScrolling else {
                return
            }
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .onChange(of: track.id) {
            isHovered = Self.hoverStateAfterTrackIdentityChange(
                isHovered: isHovered,
                isLiveScrolling: isLiveScrolling
            )
            isFavoriteFocused = false
            isActionControlFocused = false
            isContentControlFocused = false
            isActionControlAccessibilityFocused = false
        }
        .onChange(of: liveScrollPresentation) {
            workProbe?.recordLiveScrollPresentationChange(
                usesLightweightPresentation:
                liveScrollPresentation == .pointerScrolling
            )
        }
    }

    private var rowLayout: some View {
        HStack(spacing: TrackTableColumnPolicy.columnSpacing) {
            song
                .frame(width: CGFloat(widths.song), alignment: .leading)

            ForEach(columns) { column in
                columnValue(column)
                    .frame(
                        width: CGFloat(widths[column]),
                        alignment: column == .album ? .leading : .trailing
                    )
            }

            Spacer(minLength: 0)

            actionControl
        }
        .padding(.horizontal, TrackTableColumnPolicy.horizontalInset)
        .frame(height: 58)
        .background {
            BrowserRowSurface(
                isSelected: isSelected,
                isHovered: isHovered,
                isFocused: isFocused
            )
            .padding(
                .horizontal,
                TrackTableColumnPolicy.selectionHorizontalInset
            )
            .padding(.vertical, 3)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var interactiveRow: some View {
        rowLayout
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(count: 1, perform: select)
            .contextMenu {
                actionMenuContent
            }
            .draggable(dragPayload)
            .dropDestination(for: String.self) { values, _ in
                _ = reorder(values)
            }
    }

    private var lightweightPointerScrollRow: some View {
        HStack(spacing: TrackTableColumnPolicy.columnSpacing) {
            lightweightSong
                .frame(width: CGFloat(widths.song), alignment: .leading)

            ForEach(columns) { column in
                lightweightColumnValue(column)
                    .frame(
                        width: CGFloat(widths[column]),
                        alignment: column == .album ? .leading : .trailing
                    )
            }

            Spacer(minLength: 0)

            Image(systemName: Self.lightweightActionSymbolName)
                .foregroundStyle(.tertiary)
                .frame(
                    width: TrackTableColumnPolicy.actionWidth,
                    height: TrackTableColumnPolicy.actionWidth
                )
                .accessibilityHidden(true)
        }
        .padding(.horizontal, TrackTableColumnPolicy.horizontalInset)
        .frame(height: 58)
        .background {
            BrowserRowSurface(
                isSelected: isSelected,
                isHovered: false,
                isFocused: isFocused
            )
            .padding(.vertical, 3)
            .padding(
                .horizontal,
                TrackTableColumnPolicy.selectionHorizontalInset
            )
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { isHovered = $0 }
    }

    private var actionControl: some View {
        Menu {
            actionMenuContent
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(isHovered ? .primary : .tertiary)
                .frame(
                    width: TrackTableColumnPolicy.actionWidth,
                    height: TrackTableColumnPolicy.actionWidth
                )
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .focused($isActionControlFocused)
        .accessibilityFocused($isActionControlAccessibilityFocused)
        .accessibilityLabel("Track Actions")
        .help("Track Actions")
        .disabled(!ownsPlaylistContext)
    }

    private var song: some View {
        HStack(spacing: TrackTableColumnPolicy.songContentSpacing) {
            favoriteControl

            artworkControl

            songMetadata

            Spacer(minLength: 0)
        }
    }

    private var lightweightSong: some View {
        HStack(spacing: TrackTableColumnPolicy.songContentSpacing) {
            Image(
                systemName: Self.lightweightFavoriteSymbolName(
                    isFavorite: track.isFavorite
                )
            )
            .foregroundStyle(
                track.isFavorite ? Color.accentColor : Color.secondary
            )
            .frame(
                width: TrackTableColumnPolicy.favoriteControlWidth,
                height: TrackTableColumnPolicy.favoriteControlWidth
            )
            .accessibilityHidden(true)

            artwork(
                showsHoverOverlay: false,
                animatesCurrentTrack: false
            )

            lightweightSongMetadata

            Spacer(minLength: 0)
        }
    }

    private var favoriteControl: some View {
        FavoriteButton(
            itemID: track.id,
            isFavorite: track.isFavorite,
            itemName: track.title,
            controlSize: TrackTableColumnPolicy.favoriteControlWidth
        ) { requestedValue in
            await model.setProductionTrackFavorite(
                track,
                isFavorite: requestedValue
            ) != nil
        }
        .focused($isFavoriteFocused)
        .opacity(favoritePresentation.visualOpacity)
        .allowsHitTesting(favoritePresentation.acceptsPointerInteraction)
        .accessibilityHidden(!favoritePresentation.isAccessibilityVisible)
        .animation(
            reduceMotion
                ? nil
                : .easeOut(duration: CadenceTheme.motionHover),
            value: favoritePresentation.visualOpacity
        )
    }

    private var artworkControl: some View {
        Button {
            play()
        } label: {
            artwork(
                showsHoverOverlay: true,
                animatesCurrentTrack: !isLiveScrolling
            )
        }
        .buttonStyle(.plain)
        .focused($isContentControlFocused)
        .help("Play \(track.title)")
        .disabled(!ownsPlaylistContext)
    }

    private var favoritePresentation: FavoriteControlPresentation {
        FavoriteControlPresentation.resolve(
            isHovered: isHovered,
            isFocused: isFavoriteFocused
        )
    }

    private var isLiveScrolling: Bool {
        interactionState?.isLiveScrolling ?? false
    }

    private var liveScrollPresentation: TrackRowLiveScrollPresentation {
        TrackRowLiveScrollPresentation.resolve(
            isLiveScrolling: isLiveScrolling,
            isSelected: isSelected,
            isFocused: isFocused,
            isControlFocused: isFavoriteFocused
                || isActionControlFocused
                || isContentControlFocused,
            isAccessibilityFocused: isActionControlAccessibilityFocused,
            isAssistiveTechnologyEnabled: voiceOverEnabled
                || switchControlEnabled
        )
    }

    private func artwork(
        showsHoverOverlay: Bool,
        animatesCurrentTrack: Bool
    ) -> some View {
        ProductionArtworkView(
            model: model,
            artworkID: track.artworkID,
            title: track.title,
            placeholder: .track,
            variant: .trackRow,
            cornerRadius: CadenceTheme.radiusControl,
            artworkLoader: artworkLoader,
            workProbe: artworkWorkProbe,
            sharedLoadState: artworkLoadState
        )
        .frame(width: 40, height: 40)
        .overlay {
            if (showsHoverOverlay && isHovered)
                || model.isCurrentProductionTrack(track.id) {
                let isPlayingCurrentTrack = model.isCurrentProductionTrack(
                    track.id
                ) && model.isCurrentProductionTrackPlaying
                RoundedRectangle(
                    cornerRadius: CadenceTheme.radiusControl,
                    style: .continuous
                )
                .fill(.black.opacity(0.34))
                if reduceMotion || !animatesCurrentTrack {
                    Image(
                        systemName: Self.artworkOverlaySymbolName(
                            isCurrentTrack: model.isCurrentProductionTrack(
                                track.id
                            ),
                            isPlaying: model.isCurrentProductionTrackPlaying
                        )
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                } else {
                    Image(
                        systemName: Self.artworkOverlaySymbolName(
                            isCurrentTrack: model.isCurrentProductionTrack(
                                track.id
                            ),
                            isPlaying: model.isCurrentProductionTrackPlaying
                        )
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(
                        .variableColor.iterative,
                        options: .repeating,
                        isActive: isPlayingCurrentTrack
                    )
                }
            }
        }
    }
}

private extension ProductionTrackTableRow {
    @ViewBuilder
    var actionMenuContent: some View {
        if actionMenuMaterializationPolicy.materializesFullActions(
            isHovered: isHovered,
            isSelected: isSelected,
            isFocused: isFocused,
            isKeyboardFocused: isActionControlFocused,
            isAccessibilityFocused: isActionControlAccessibilityFocused,
            isLiveScrolling: isLiveScrolling
        ) {
            actions
        } else {
            Button("Track Actions") {}
                .disabled(true)
                .accessibilityLabel("Track Actions")
        }
    }
}

extension ProductionTrackTableRow {
    static let lightweightActionSymbolName = "ellipsis"

    static func lightweightFavoriteSymbolName(
        isFavorite: Bool
    ) -> String {
        isFavorite ? "heart.fill" : "heart"
    }

    static func hoverStateAfterTrackIdentityChange(
        isHovered: Bool,
        isLiveScrolling: Bool
    ) -> Bool {
        isLiveScrolling ? isHovered : false
    }
}
