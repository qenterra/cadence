@testable import Cadence
import Testing

struct ArtistCreditParserTests {
    @Test("Artist credits split only approved separators and preserve order")
    func approvedSeparators() {
        let parser = ArtistCreditParser()

        #expect(
            parser.parse(
                values: [
                    "madkid, темный принц",
                    "Guest feat. Another; Final ft Last",
                ],
                fallback: "Unknown Artist"
            ) == [
                "madkid",
                "темный принц",
                "Guest",
                "Another",
                "Final",
                "Last",
            ]
        )
    }

    @Test("Ampersand x slash and and remain inside artist names")
    func preservedSeparators() {
        #expect(
            ArtistCreditParser().parse(
                values: ["Earth, Wind & Fire x AC/DC and Friends"],
                fallback: "Unknown Artist"
            ) == ["Earth", "Wind & Fire x AC/DC and Friends"]
        )
    }

    @Test("Credits deduplicate case-insensitively and use fallback")
    func deduplicationAndFallback() {
        let parser = ArtistCreditParser()

        #expect(
            parser.parse(
                values: ["madkid; MADKID; темный принц"],
                fallback: "Unknown Artist"
            ) == ["madkid", "темный принц"]
        )
        #expect(
            parser.parse(values: [], fallback: "Unknown Artist")
                == ["Unknown Artist"]
        )
    }
}
