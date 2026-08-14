import Foundation

struct TagPreview: Identifiable, Hashable, Sendable {
    let id: String
    let components: [String]

    init?(path: String) {
        let components = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
            }

        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }

        self.components = components
        id = components.joined(separator: "/")
    }

    var displayName: String {
        components.last.map(Self.displayText) ?? Self.displayText(id)
    }

    var displayPath: String {
        components.map(Self.displayText).joined(separator: " / ")
    }

    var groupID: TagGroupID {
        guard components.count > 1, let group = components.first else {
            return .standalone
        }
        return .hierarchy(group)
    }

    private static func displayText(_ component: String) -> String {
        component
            .replacingOccurrences(of: "-", with: " ")
            .localizedCapitalized
    }
}

enum TagPathValidationError: Hashable, Sendable {
    case empty
    case emptyComponent
}

extension TagPreview {
    static func validationError(
        for path: String
    ) -> TagPathValidationError? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return .empty
        }

        let components = trimmedPath.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        return components.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ? .emptyComponent : nil
    }
}

enum TagGroupID: Hashable, Sendable {
    case all
    case hierarchy(String)
    case standalone

    var title: String {
        switch self {
        case .all:
            String(localized: "All Tags")
        case let .hierarchy(name):
            name.localizedCapitalized
        case .standalone:
            String(localized: "Standalone")
        }
    }
}

struct TagGroupPreview: Identifiable, Hashable, Sendable {
    let id: TagGroupID
    let tagCount: Int

    var title: String {
        id.title
    }
}

enum TagAssignmentTarget: Hashable, Sendable {
    case album(AlbumPreview.ID)
    case track(TrackPreview.ID)
}

struct TagAssignmentPreview: Hashable, Sendable {
    let tagID: TagPreview.ID
    let target: TagAssignmentTarget
}

struct TagExclusionPreview: Hashable, Sendable {
    let tagID: TagPreview.ID
    let trackID: TrackPreview.ID
}

enum TagResultScope: String, CaseIterable, Identifiable, Sendable {
    case tracks
    case albums

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .tracks:
            String(localized: "Tracks")
        case .albums:
            String(localized: "Albums")
        }
    }
}

enum TrackTagMatchSource: String, Hashable, Sendable {
    case direct
    case inherited
}

struct TaggedTrackPreview: Identifiable, Hashable, Sendable {
    let track: TrackPreview
    let source: TrackTagMatchSource

    var id: TrackPreview.ID {
        track.id
    }
}

enum AlbumTagMatchSource: String, Hashable, Sendable {
    case album
    case track
}

struct TaggedAlbumPreview: Identifiable, Hashable, Sendable {
    let album: AlbumPreview
    let source: AlbumTagMatchSource

    var id: AlbumPreview.ID {
        album.id
    }
}
