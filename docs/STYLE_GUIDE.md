# Style guide

## Language

Public code identifiers, repository documentation, issues, pull requests, commits, and release notes use English. Preserve exact product names, APIs, standards, and user-facing localisations where required.

## Names and layout

- Repository and general directories use lowercase `kebab-case`.
- GitHub community and legal root files use their canonical uppercase names.
- Swift types and files use `UpperCamelCase`; members and test methods use `lowerCamelCase`; asset and localisation identifiers follow their owning Apple format.
- New top-level paths require an architectural or tooling reason and a documentation update.

## Code

SwiftFormat is the canonical formatter and SwiftLint is the canonical linter; their versioned configuration is authoritative. Prefer explicit interfaces and bounded responsibilities, preserve actor and main-thread isolation, and document non-obvious persistence, playback, and recovery invariants rather than narrating syntax.

## Documentation

Use descriptive headings, portable Markdown, runnable examples, meaningful link text, image alternative text, and one source of truth per durable subject. Do not publish placeholders or internal agent prose.

## Accessibility and inclusive language

Treat keyboard access, assistive technology, contrast, reduced motion, localisation, and clear error text as product requirements where the profile exposes an interface.
