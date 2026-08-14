import Foundation

extension CadenceAppModel {
    var tagGroups: [TagGroupPreview] {
        let groupedTags = Dictionary(grouping: tags, by: \.groupID)
        let groups = groupedTags.map { groupID, tags in
            TagGroupPreview(id: groupID, tagCount: tags.count)
        }
        .sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }

        return [TagGroupPreview(id: .all, tagCount: tags.count)] + groups
    }

    var tagsForSelectedGroup: [TagPreview] {
        tags(in: selectedTagGroupID)
    }

    var selectedTag: TagPreview? {
        tags.first { $0.id == selectedTagID }
    }

    var taggedTracks: [TaggedTrackPreview] {
        guard let selectedTagID else {
            return []
        }

        return tracks.compactMap { track in
            guard let source = tagMatchSource(for: track, tagID: selectedTagID) else {
                return nil
            }
            return TaggedTrackPreview(track: track, source: source)
        }
        .sorted {
            trackComesBefore($0.track, $1.track)
        }
    }

    var taggedAlbums: [TaggedAlbumPreview] {
        guard let selectedTagID else {
            return []
        }

        return albums.compactMap { album in
            guard let source = albumMatchSource(for: album, tagID: selectedTagID) else {
                return nil
            }
            return TaggedAlbumPreview(album: album, source: source)
        }
    }

    func effectiveTags(for track: TrackPreview) -> [TagPreview] {
        let direct = tagIDs(assignedTo: .track(track.id))
        let excluded = Set(
            tagExclusions
                .filter { $0.trackID == track.id }
                .map(\.tagID)
        )
        let inherited = tagIDs(assignedTo: .album(track.albumID))
            .subtracting(excluded)
        let effective = direct.union(inherited)

        return sortedTags(tags.filter { effective.contains($0.id) })
    }

    func assignedTags(for album: AlbumPreview) -> [TagPreview] {
        let assigned = tagIDs(assignedTo: .album(album.id))
        return sortedTags(tags.filter { assigned.contains($0.id) })
    }

    func trackTagItems(for track: TrackPreview) -> [AlbumTrackTagItem] {
        let direct = tagIDs(assignedTo: .track(track.id))
        let inherited = tagIDs(assignedTo: .album(track.albumID))
        let excluded = Set(
            tagExclusions
                .filter { $0.trackID == track.id }
                .map(\.tagID)
        )
        let visible = direct.union(inherited)

        return sortedTags(tags.filter { visible.contains($0.id) })
            .map { tag in
                let source: AlbumTrackTagSource = if direct.contains(tag.id) {
                    .direct
                } else if excluded.contains(tag.id) {
                    .excluded
                } else {
                    .inherited
                }
                return AlbumTrackTagItem(tag: tag, source: source)
            }
    }

    func tagMatchSource(
        for track: TrackPreview,
        tagID: TagPreview.ID
    ) -> TrackTagMatchSource? {
        if hasAssignment(tagID: tagID, target: .track(track.id)) {
            return .direct
        }

        let isExcluded = tagExclusions.contains {
            $0.trackID == track.id && $0.tagID == tagID
        }
        if !isExcluded, hasAssignment(tagID: tagID, target: .album(track.albumID)) {
            return .inherited
        }
        return nil
    }

    func selectTagGroup(_ group: TagGroupPreview) {
        if selectedTagGroupID != group.id {
            clearTagEditingSelection()
        }
        selectedTagGroupID = group.id
        let visibleTags = tags(in: group.id)
        guard visibleTags.contains(where: { $0.id == selectedTagID }) else {
            selectedTagID = visibleTags.first?.id
            return
        }
    }

    func selectTag(_ tag: TagPreview) {
        if selectedTagID != tag.id {
            clearTagEditingSelection()
        }
        selectedTagID = tag.id
    }

    func selectTagResultScope(_ scope: TagResultScope) {
        guard tagResultScope != scope else {
            return
        }
        clearTagEditingSelection()
        tagResultScope = scope
    }

    private func tags(in groupID: TagGroupID) -> [TagPreview] {
        let matchingTags = switch groupID {
        case .all:
            tags
        case .standalone, .hierarchy:
            tags.filter { $0.groupID == groupID }
        }
        return sortedTags(matchingTags)
    }

    private func sortedTags(_ tags: [TagPreview]) -> [TagPreview] {
        tags.sorted {
            $0.displayPath.localizedStandardCompare($1.displayPath) == .orderedAscending
        }
    }

    private func tagIDs(assignedTo target: TagAssignmentTarget) -> Set<TagPreview.ID> {
        Set(
            tagAssignments
                .filter { $0.target == target }
                .map(\.tagID)
        )
    }

    private func hasAssignment(
        tagID: TagPreview.ID,
        target: TagAssignmentTarget
    ) -> Bool {
        tagAssignments.contains(
            TagAssignmentPreview(tagID: tagID, target: target)
        )
    }

    private func albumMatchSource(
        for album: AlbumPreview,
        tagID: TagPreview.ID
    ) -> AlbumTagMatchSource? {
        if hasAssignment(tagID: tagID, target: .album(album.id)) {
            return .album
        }

        let hasDirectTrackMatch = tracks.contains { track in
            track.albumID == album.id
                && hasAssignment(tagID: tagID, target: .track(track.id))
        }
        return hasDirectTrackMatch ? .track : nil
    }

    private func trackComesBefore(
        _ lhs: TrackPreview,
        _ rhs: TrackPreview
    ) -> Bool {
        let artistOrder = lhs.artist.localizedStandardCompare(rhs.artist)
        if artistOrder != .orderedSame {
            return artistOrder == .orderedAscending
        }

        let albumOrder = lhs.album.localizedStandardCompare(rhs.album)
        if albumOrder != .orderedSame {
            return albumOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}
