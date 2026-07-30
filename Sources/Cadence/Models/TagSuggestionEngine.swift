import Foundation

struct TagSuggestionEngine {
    let tracks: [TrackPreview]
    let tags: [TagPreview]
    let assignments: Set<TagAssignmentPreview>
    let exclusions: Set<TagExclusionPreview>
    let dismissals: Set<TagSuggestionDismissal>

    func suggestions(
        for targets: [TagAssignmentTarget]
    ) -> [TagSuggestion] {
        let candidates = targets.flatMap(candidates(for:))
        let groupedCandidates = Dictionary(grouping: candidates, by: \.tag.id)

        return groupedCandidates.compactMap { _, candidates in
            guard let bestCandidate = candidates.min(by: candidateComesBefore) else {
                return nil
            }
            let eligibleTargets = targets.filter { target in
                candidates.contains { $0.target == target }
            }
            return TagSuggestion(
                tag: bestCandidate.tag,
                evidence: bestCandidate.evidence,
                supportCount: bestCandidate.supportCount,
                reason: bestCandidate.reason,
                eligibleTargets: eligibleTargets,
                selectionCount: targets.count
            )
        }
        .sorted(by: suggestionComesBefore)
    }
}

private extension TagSuggestionEngine {
    private func candidates(
        for target: TagAssignmentTarget
    ) -> [TagSuggestionCandidate] {
        let ineligibleTagIDs = ineligibleTagIDs(for: target)
        return tags.compactMap { tag in
            guard !ineligibleTagIDs.contains(tag.id) else {
                return nil
            }

            switch target {
            case let .track(trackID):
                return trackCandidate(tag: tag, trackID: trackID)
            case let .album(albumID):
                return albumCandidate(tag: tag, albumID: albumID)
            }
        }
    }

    private func trackCandidate(
        tag: TagPreview,
        trackID: TrackPreview.ID
    ) -> TagSuggestionCandidate? {
        guard let track = tracks.first(where: { $0.id == trackID }) else {
            return nil
        }

        let evidence = [
            trackAlbumEvidence(tag: tag, track: track),
            trackArtistEvidence(tag: tag, track: track),
            trackCooccurrenceEvidence(tag: tag, track: track),
        ]
        .compactMap(\.self)
        .min(by: evidenceComesBefore)

        guard let evidence else {
            return nil
        }
        return TagSuggestionCandidate(
            tag: tag,
            target: .track(trackID),
            evidence: evidence.kind,
            supportCount: evidence.supportCount,
            reason: evidence.reason
        )
    }
}

private extension TagSuggestionEngine {
    private func albumCandidate(
        tag: TagPreview,
        albumID: AlbumPreview.ID
    ) -> TagSuggestionCandidate? {
        guard let firstTrack = tracks.first(where: { $0.albumID == albumID }) else {
            return nil
        }

        let evidence = [
            albumTrackEvidence(tag: tag, albumID: albumID),
            albumArtistEvidence(tag: tag, albumID: albumID, artist: firstTrack.artist),
        ]
        .compactMap(\.self)
        .min(by: evidenceComesBefore)

        guard let evidence else {
            return nil
        }
        return TagSuggestionCandidate(
            tag: tag,
            target: .album(albumID),
            evidence: evidence.kind,
            supportCount: evidence.supportCount,
            reason: evidence.reason
        )
    }

    private func trackAlbumEvidence(
        tag: TagPreview,
        track: TrackPreview
    ) -> SuggestionEvidence? {
        let peers = tracks.filter {
            $0.albumID == track.albumID && $0.id != track.id
        }
        let supportCount = peers.filter {
            hasDirectAssignment(tagID: tag.id, target: .track($0.id))
        }.count

        guard supportCount >= 2, supportCount * 2 >= peers.count else {
            return nil
        }
        return SuggestionEvidence(
            kind: .album,
            supportCount: supportCount,
            reason: "Used by \(supportCount) other tracks on this album"
        )
    }

    private func trackArtistEvidence(
        tag: TagPreview,
        track: TrackPreview
    ) -> SuggestionEvidence? {
        let supportingTracks = tracks.filter {
            $0.artistID == track.artistID
                && $0.albumID != track.albumID
                && effectiveTagIDs(for: $0).contains(tag.id)
        }
        let albumCount = Set(supportingTracks.map(\.albumID)).count
        guard supportingTracks.count >= 3, albumCount >= 2 else {
            return nil
        }

        return SuggestionEvidence(
            kind: .artist,
            supportCount: supportingTracks.count,
            reason: "Used across \(albumCount) other albums by this artist"
        )
    }

    private func trackCooccurrenceEvidence(
        tag: TagPreview,
        track: TrackPreview
    ) -> SuggestionEvidence? {
        effectiveTagIDs(for: track).compactMap { seedTagID in
            let carriers = tracks.filter {
                $0.id != track.id && effectiveTagIDs(for: $0).contains(seedTagID)
            }
            let supportCount = carriers.filter {
                effectiveTagIDs(for: $0).contains(tag.id)
            }.count
            guard
                supportCount >= 3,
                supportCount * 5 >= carriers.count * 3
            else {
                return nil
            }
            return SuggestionEvidence(
                kind: .cooccurrence,
                supportCount: supportCount,
                reason: "Often paired with \(seedTagID)"
            )
        }
        .min(by: evidenceComesBefore)
    }
}

private extension TagSuggestionEngine {
    private func albumTrackEvidence(
        tag: TagPreview,
        albumID: AlbumPreview.ID
    ) -> SuggestionEvidence? {
        let albumTracks = tracks.filter { $0.albumID == albumID }
        let supportCount = albumTracks.filter {
            hasDirectAssignment(tagID: tag.id, target: .track($0.id))
        }.count

        guard
            supportCount >= 2,
            supportCount * 5 >= albumTracks.count * 3
        else {
            return nil
        }
        return SuggestionEvidence(
            kind: .album,
            supportCount: supportCount,
            reason: "Used by \(supportCount) tracks on this album"
        )
    }

    private func albumArtistEvidence(
        tag: TagPreview,
        albumID: AlbumPreview.ID,
        artist: String
    ) -> SuggestionEvidence? {
        let otherAlbumIDs = Set(
            tracks
                .filter { $0.artist == artist && $0.albumID != albumID }
                .map(\.albumID)
        )
        let supportCount = otherAlbumIDs.filter {
            hasDirectAssignment(tagID: tag.id, target: .album($0))
        }.count
        guard supportCount >= 2 else {
            return nil
        }
        return SuggestionEvidence(
            kind: .artist,
            supportCount: supportCount,
            reason: "Used across \(supportCount) other albums by this artist"
        )
    }

    private func ineligibleTagIDs(
        for target: TagAssignmentTarget
    ) -> Set<TagPreview.ID> {
        var tagIDs = effectiveTagIDs(for: target)
        switch target {
        case let .track(trackID):
            tagIDs.formUnion(
                exclusions
                    .filter { $0.trackID == trackID }
                    .map(\.tagID)
            )
        case .album:
            break
        }
        tagIDs.formUnion(
            dismissals
                .filter { $0.target == target }
                .map(\.tagID)
        )
        return tagIDs
    }

    private func effectiveTagIDs(
        for target: TagAssignmentTarget
    ) -> Set<TagPreview.ID> {
        switch target {
        case let .track(trackID):
            guard let track = tracks.first(where: { $0.id == trackID }) else {
                return []
            }
            return effectiveTagIDs(for: track)
        case .album:
            return directTagIDs(for: target)
        }
    }

    private func effectiveTagIDs(
        for track: TrackPreview
    ) -> Set<TagPreview.ID> {
        let excludedTagIDs = Set(
            exclusions
                .filter { $0.trackID == track.id }
                .map(\.tagID)
        )
        let inheritedTagIDs = directTagIDs(for: .album(track.albumID))
            .subtracting(excludedTagIDs)
        return directTagIDs(for: .track(track.id))
            .union(inheritedTagIDs)
    }

    private func directTagIDs(
        for target: TagAssignmentTarget
    ) -> Set<TagPreview.ID> {
        Set(
            assignments
                .filter { $0.target == target }
                .map(\.tagID)
        )
    }

    private func hasDirectAssignment(
        tagID: TagPreview.ID,
        target: TagAssignmentTarget
    ) -> Bool {
        assignments.contains(
            TagAssignmentPreview(tagID: tagID, target: target)
        )
    }

    private func candidateComesBefore(
        _ lhs: TagSuggestionCandidate,
        _ rhs: TagSuggestionCandidate
    ) -> Bool {
        if lhs.evidence != rhs.evidence {
            return lhs.evidence.rawValue < rhs.evidence.rawValue
        }
        if lhs.supportCount != rhs.supportCount {
            return lhs.supportCount > rhs.supportCount
        }
        return lhs.tag.displayPath.localizedStandardCompare(rhs.tag.displayPath)
            == .orderedAscending
    }

    private func suggestionComesBefore(
        _ lhs: TagSuggestion,
        _ rhs: TagSuggestion
    ) -> Bool {
        if lhs.evidence != rhs.evidence {
            return lhs.evidence.rawValue < rhs.evidence.rawValue
        }
        if lhs.eligibleTargets.count != rhs.eligibleTargets.count {
            return lhs.eligibleTargets.count > rhs.eligibleTargets.count
        }
        if lhs.supportCount != rhs.supportCount {
            return lhs.supportCount > rhs.supportCount
        }
        return lhs.tag.displayPath.localizedStandardCompare(rhs.tag.displayPath)
            == .orderedAscending
    }

    private func evidenceComesBefore(
        _ lhs: SuggestionEvidence,
        _ rhs: SuggestionEvidence
    ) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        if lhs.supportCount != rhs.supportCount {
            return lhs.supportCount > rhs.supportCount
        }
        return lhs.reason.localizedStandardCompare(rhs.reason) == .orderedAscending
    }
}

private struct SuggestionEvidence {
    let kind: TagSuggestionEvidence
    let supportCount: Int
    let reason: String
}
