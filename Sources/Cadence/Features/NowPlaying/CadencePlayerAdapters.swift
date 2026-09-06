import Foundation
import QenTerraMediaComponents

struct CadencePlayerItemSnapshot: Equatable, Sendable {
    let id: UUID
    let title: String
    let artist: String
    let isExternal: Bool
}

struct CadencePlayerBarSnapshot: Equatable, Sendable {
    let item: CadencePlayerItemSnapshot?
    let isPlaying: Bool
    let isShuffleEnabled: Bool
    let repeatMode: RepeatMode
    let presentationTime: TimeInterval
    let duration: TimeInterval
    let volume: Double
    let isMuted: Bool
    let isQueuePresented: Bool
    let timeDisplayMode: PlaybackTimeDisplayMode
    let libraryTrackCount: Int

    static func empty(libraryTrackCount: Int) -> Self {
        Self(
            item: nil,
            isPlaying: false,
            isShuffleEnabled: false,
            repeatMode: .off,
            presentationTime: 0,
            duration: 0,
            volume: 0,
            isMuted: false,
            isQueuePresented: false,
            timeDisplayMode: .elapsed,
            libraryTrackCount: libraryTrackCount
        )
    }
}

struct CadencePlayerBarAdapterPresentation: Equatable, Sendable {
    let presentation: QenTerraMediaComponents.PlayerBarPresentation
    let itemID: UUID?
    let showsExternalImportAction: Bool
    let showsFavoriteAccessory: Bool
}

struct CadenceQueueRowSnapshot: Equatable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let durationText: String?
    let isAvailable: Bool
}

enum CadencePlayerAdapters {
    static func playerBar(
        from snapshot: CadencePlayerBarSnapshot,
        pendingSeekProgress: Double? = nil
    ) -> CadencePlayerBarAdapterPresentation {
        let item = snapshot.item
        let duration = validDuration(snapshot.duration)
        let presentationTime = pendingSeekProgress.map { duration * clamp($0) }
            ?? max(snapshot.presentationTime.isFinite ? snapshot.presentationTime : 0, 0)
        let progress = duration > 0 ? clamp(presentationTime / duration) : 0
        let empty = PlayerBarEmptyPresentation(libraryTrackCount: snapshot.libraryTrackCount)
        let leadingText = PlaybackTimePresentation.leadingText(
            mode: snapshot.timeDisplayMode,
            currentTime: presentationTime,
            duration: duration
        )

        return CadencePlayerBarAdapterPresentation(
            presentation: QenTerraMediaComponents.PlayerBarPresentation(
                title: item?.title,
                subtitle: item?.artist,
                isPlaying: snapshot.isPlaying,
                isShuffleEnabled: snapshot.isShuffleEnabled,
                repeatMode: transportRepeatMode(snapshot.repeatMode),
                progress: PlaybackProgressPresentation(
                    progress: progress,
                    leadingText: item == nil ? "0:00" : leadingText,
                    trailingText: item == nil ? "0:00" : TrackPreview.timeText(duration),
                    accessibilityLabel: String(localized: "Playback progress"),
                    isEnabled: item != nil && duration > 0
                ),
                volume: snapshot.volume,
                isMuted: snapshot.isMuted,
                isQueuePresented: snapshot.isQueuePresented,
                favorite: nil,
                showNowPlayingAccessibilityLabel: item.map {
                    "Show Now Playing for \($0.title) by \($0.artist)"
                },
                emptyTitle: item == nil ? empty.title : nil,
                emptySymbolName: item == nil ? empty.symbolName : nil
            ),
            itemID: item?.id,
            showsExternalImportAction: item?.isExternal == true,
            showsFavoriteAccessory: item != nil && item?.isExternal == false
        )
    }

    static func queueRow(
        _ snapshot: CadenceQueueRowSnapshot,
        isCurrent: Bool,
        isSelected: Bool,
        isDraggable: Bool,
        isPlaying: Bool
    ) -> PlaybackQueueRowPresentation<UUID> {
        PlaybackQueueRowPresentation(
            id: snapshot.id,
            title: snapshot.title,
            subtitle: snapshot.subtitle,
            durationText: snapshot.durationText,
            isCurrent: isCurrent,
            isSelected: isSelected,
            isAvailable: snapshot.isAvailable,
            isDraggable: isDraggable,
            isPlaying: isPlaying,
            accessibilityLabel: [snapshot.title, snapshot.subtitle]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        )
    }

    static func lyricLines(
        _ lines: [LyricLine],
        activeLineID: LyricLine.ID?
    ) -> [LyricLinePresentation<LyricLine.ID>] {
        lines.map { line in
            LyricLinePresentation(
                id: line.id,
                text: line.text,
                isActive: line.id == activeLineID,
                isSynchronized: line.startTime != nil,
                isBlankStanza: line.isBlank
            )
        }
    }

    static func audioDetails(_ details: [AudioQualityDetail]) -> [AudioDetail] {
        var occurrences: [String: Int] = [:]
        return details.enumerated().map { index, detail in
            let base = detail.label
                .lowercased()
                .replacingOccurrences(
                    of: "[^a-z0-9]+",
                    with: "-",
                    options: .regularExpression
                )
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            let id = occurrence == 0 ? base : "\(base)-\(occurrence + 1)"
            return AudioDetail(id: id, label: detail.label, value: detail.value, order: index)
        }
    }

    private static func transportRepeatMode(_ mode: RepeatMode) -> TransportRepeatMode {
        switch mode {
        case .off: .off
        case .all: .all
        case .one: .one
        }
    }

    private static func validDuration(_ duration: TimeInterval) -> TimeInterval {
        duration.isFinite ? max(duration, 0) : 0
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct CadencePendingSeekState: Equatable, Sendable {
    struct Token: Equatable, Sendable {
        fileprivate let generation: UInt64
        fileprivate let itemID: UUID
    }

    private(set) var progress: Double?
    private var itemID: UUID?
    private var generation: UInt64 = 0

    mutating func begin(progress: Double, itemID: UUID) -> Token {
        generation &+= 1
        self.itemID = itemID
        self.progress = progress.isFinite ? min(max(progress, 0), 1) : 0
        return Token(generation: generation, itemID: itemID)
    }

    mutating func complete(_ token: Token) {
        guard token.generation == generation, token.itemID == itemID else { return }
        progress = nil
    }

    mutating func updateCurrentItem(_ newItemID: UUID?) {
        guard newItemID != itemID else { return }
        itemID = newItemID
        progress = nil
        generation &+= 1
    }
}
