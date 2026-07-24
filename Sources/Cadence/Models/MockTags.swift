import Foundation

extension [TagPreview] {
    static let mockTags: [TagPreview] = [
        "genre/ambient",
        "genre/drone",
        "genre/electronic",
        "genre/jazz",
        "genre/post-rock",
        "genre/shoegaze",
        "mood/calm",
        "mood/hopeful",
        "mood/sad",
        "context/focus",
        "context/night",
        "context/rainy-day",
        "childhood",
        "demo",
        "roadtrip",
    ].compactMap(TagPreview.init(path:))
}

extension Set<TagAssignmentPreview> {
    static let mockTagAssignments: Set<TagAssignmentPreview> = [
        albumAssignment("genre/ambient", "North Assembly", "Signals After Dark"),
        albumAssignment("genre/electronic", "North Assembly", "Signals After Dark"),
        albumAssignment("context/night", "North Assembly", "Signals After Dark"),
        albumAssignment("genre/electronic", "North Assembly", "Midnight Static"),
        albumAssignment("context/night", "North Assembly", "Midnight Static"),
        albumAssignment("genre/drone", "North Assembly", "Transient Lines"),
        albumAssignment("mood/calm", "Mara Vale", "Quiet Machines"),
        albumAssignment("genre/shoegaze", "Glass District", "Pale Signals"),
        albumAssignment("childhood", "Soft Archive", "Recovered Light"),
        trackAssignment("mood/sad", 1),
        trackAssignment("mood/calm", 2),
        trackAssignment("mood/calm", 3),
        trackAssignment("mood/calm", 4),
        trackAssignment("mood/calm", 5),
        trackAssignment("mood/calm", 6),
        trackAssignment("mood/calm", 7),
        trackAssignment("mood/calm", 8),
        trackAssignment("mood/calm", 9),
        trackAssignment("roadtrip", 13),
        trackAssignment("context/focus", 13),
        trackAssignment("context/focus", 15),
        trackAssignment("context/focus", 17),
        trackAssignment("demo", 18),
        trackAssignment("genre/ambient", 31),
        trackAssignment("context/night", 29),
        trackAssignment("mood/hopeful", 25),
        trackAssignment("genre/jazz", 30),
        trackAssignment("genre/post-rock", 27),
    ]

    private static func albumAssignment(
        _ tagID: TagPreview.ID,
        _ artist: String,
        _ album: String
    ) -> TagAssignmentPreview {
        TagAssignmentPreview(
            tagID: tagID,
            target: .album("\(artist)\u{1F}\(album)")
        )
    }

    private static func trackAssignment(
        _ tagID: TagPreview.ID,
        _ trackID: TrackPreview.ID
    ) -> TagAssignmentPreview {
        TagAssignmentPreview(tagID: tagID, target: .track(trackID))
    }
}

extension Set<TagExclusionPreview> {
    static let mockTagExclusions: Set<TagExclusionPreview> = [
        TagExclusionPreview(tagID: "context/night", trackID: 9),
    ]
}
