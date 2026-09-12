# Tags and Collections

Cadence separates descriptive tags, rule-based smart collections, and manually
ordered playlists. They solve different jobs and do not rewrite audio metadata.

## Tags

Tags can be standalone:

```text
childhood
```

or hierarchical:

```text
genre/ambient
mood/sad
context/rainy-day
```

A track can receive a direct assignment. An album assignment is inherited by
its tracks. A track-level exclusion can suppress an inherited tag without
removing the album assignment.

## Assigning tracks

The selected tag exposes **Add Tracks…**. Its production library sheet supports
search, Command-click, Shift-click, and Command-A. Tracks already assigned
directly are marked and excluded from the pending batch. Saving performs one
repository transaction rather than one write per row.

Tags can also be edited from Now Playing and a track's context menu. Album
actions may apply a tag to the album so its tracks inherit it.

## Smart Collections

A smart collection stores nested rules and evaluates matching tracks without
duplicating or moving media. Groups can match **All** or **Any** child rules;
rules can use fields such as tag, artist, album, year, favorite state, duration,
format, or play history where supported by the current schema.

The editor is separate from the listening view. Users build rules in the editor
and play the resulting collection from its normal collection page.

## Playlists

Playlists contain explicit ordered track references. Their order is manual and
does not change when metadata or tags change. Use a playlist when sequence
matters; use a smart collection when membership should follow rules.


See [Library and Import](Library-And-Import) and [Feature Overview](Feature-Overview).
