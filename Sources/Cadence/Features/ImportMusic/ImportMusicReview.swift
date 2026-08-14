import AppKit
import SwiftUI

enum ImportMusicReviewLayout {
    enum Mode: Equatable {
        case compact
        case full
    }

    private static let fullTableMinimumWidth = 950.0
    private static let compactTableMinimumWidth = 670.0

    static func mode(for availableWidth: Double) -> Mode {
        availableWidth >= fullTableMinimumWidth ? .full : .compact
    }

    static func minimumContentWidth(for mode: Mode) -> Double {
        switch mode {
        case .compact:
            compactTableMinimumWidth
        case .full:
            fullTableMinimumWidth
        }
    }
}

struct ImportMusicReview: View {
    @Bindable var model: CadenceAppModel

    let isImporting: Bool
    let importingStatusLabel: LocalizedStringKey
    let importProgressText: LocalizedStringKey
    let canCancelImport: Bool
    let cancelImport: () -> Void

    var body: some View {
        GeometryReader { geometry in
            reviewContent(
                layoutMode: ImportMusicReviewLayout.mode(
                    for: geometry.size.width
                )
            )
        }
    }

    private func reviewContent(
        layoutMode: ImportMusicReviewLayout.Mode
    ) -> some View {
        VStack(spacing: 0) {
            reviewTabs
            tableHeader(layoutMode: layoutMode)
            Divider()

            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(model.visibleImportCandidates) { candidate in
                        ImportMusicCandidateRow(
                            model: model,
                            candidate: candidate,
                            isDisabled: isImporting,
                            layoutMode: layoutMode
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
    }

    private var reviewTabs: some View {
        HStack(spacing: 8) {
            ForEach(ImportReviewCategory.allCases) { category in
                Button {
                    model.selectImportReviewCategory(category)
                } label: {
                    HStack(spacing: 7) {
                        Text(category.title)
                        Text(model.importCandidateCount(in: category).formatted())
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background {
                        BrowserRowSurface(
                            isSelected: model.importReviewCategory == category,
                            isHovered: false,
                            isFocused: false
                        )
                    }
                }
                .buttonStyle(CadenceRowButtonStyle())
                .disabled(isImporting)
                .accessibilityValue(
                    model.importReviewCategory == category ? "Selected" : ""
                )
            }

            Spacer()

            if isImporting {
                Label(
                    importingStatusLabel,
                    systemImage: "arrow.down.circle"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            } else {
                Text("Select rows with ⌘ or ⇧ · Space toggles inclusion")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func tableHeader(
        layoutMode: ImportMusicReviewLayout.Mode
    ) -> some View {
        HStack(spacing: 10) {
            Text("")
                .frame(width: 34)
            Text("Title")
                .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
            if layoutMode == .compact {
                Text("Artist / Album")
                    .frame(width: 180, alignment: .leading)
                Text("Status / Lyrics")
                    .frame(width: 150, alignment: .leading)
            } else {
                Text("Artist")
                    .frame(width: 140, alignment: .leading)
                Text("Album")
                    .frame(width: 160, alignment: .leading)
                Text("Lyrics")
                    .frame(width: 114, alignment: .leading)
                Text("Status")
                    .frame(width: 138, alignment: .leading)
            }
            Text("Size")
                .frame(width: 72, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 22)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectionSummary)
                    .font(.callout.weight(.medium))

                Text("Exact duplicates and unavailable files stay excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isImporting {
                if canCancelImport {
                    Button("Cancel") {
                        cancelImport()
                    }
                    .buttonStyle(.bordered)
                }
                if let progress = determinateImportProgress {
                    ProgressView(
                        value: Double(progress.completedCount),
                        total: Double(progress.totalCount)
                    )
                    .frame(width: 120)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(importProgressText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Button("Choose Another Folder") {
                    model.chooseImportFolder()
                }
                .buttonStyle(.bordered)

                Button("Import \(model.importSelectedCount) Tracks") {
                    model.beginImportPreview()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canBeginImportPreview)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(CadenceTheme.secondarySurface)
    }

    private var selectionSummary: String {
        "\(model.importSelectedCount) total included · "
            + "\(model.importSelectedSizeText)"
    }

    private var determinateImportProgress: ManagedImportProgress? {
        guard
            let progress = model.managedImportProgress,
            progress.totalCount > 0
        else {
            return nil
        }
        return progress
    }
}

private struct ImportMusicCandidateRow: View {
    @Bindable var model: CadenceAppModel

    let candidate: ImportCandidatePreview
    let isDisabled: Bool
    let layoutMode: ImportMusicReviewLayout.Mode

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            inclusionButton

            Button {
                model.updateImportCandidateSelection(
                    currentImportSelectionIntent(),
                    candidateID: candidate.id
                )
            } label: {
                rowContent
                    .contentShape(Rectangle())
            }
            .buttonStyle(CadenceRowButtonStyle())
            .focused($isFocused)
            .disabled(isDisabled)
        }
        .padding(.horizontal, 8)
        .background {
            BrowserRowSurface(
                isSelected: model.isImportCandidateSelected(candidate.id),
                isHovered: isHovered,
                isFocused: isFocused
            )
        }
        .onHover { isInside in
            isHovered = isInside
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
    }

    private var inclusionButton: some View {
        Button {
            model.toggleImportCandidateInclusion(candidate.id)
        } label: {
            Image(systemName: inclusionSymbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(
                    model.isImportCandidateIncluded(candidate.id)
                        ? .primary
                        : .secondary
                )
                .frame(width: 34, height: 42)
                .contentShape(Rectangle())
        }
        .buttonStyle(CadenceRowButtonStyle())
        .disabled(!candidate.isEligible || isDisabled)
        .help(inclusionHelp)
        .accessibilityLabel(inclusionHelp)
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(candidate.sourceFilename) · \(candidate.format)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)

            if layoutMode == .compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.artist)
                    Text(candidate.album)
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    statusLabel(
                        candidate.classification.title,
                        symbolName: candidate.classification.symbolName
                    )
                    statusLabel(
                        candidate.lyricStatus.title,
                        symbolName: candidate.lyricStatus.symbolName
                    )
                }
                .frame(width: 150, alignment: .leading)
            } else {
                Text(candidate.artist)
                    .frame(width: 140, alignment: .leading)
                Text(candidate.album)
                    .frame(width: 160, alignment: .leading)
                statusLabel(
                    candidate.lyricStatus.title,
                    symbolName: candidate.lyricStatus.symbolName
                )
                .frame(width: 114, alignment: .leading)
                statusLabel(
                    candidate.classification.title,
                    symbolName: candidate.classification.symbolName
                )
                .frame(width: 138, alignment: .leading)
            }
            Text(candidate.fileSizeText)
                .monospacedDigit()
                .frame(width: 72, alignment: .trailing)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(minHeight: 48)
    }

    private func statusLabel(
        _ title: String,
        symbolName: String
    ) -> some View {
        Label(title, systemImage: symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var inclusionSymbol: String {
        if model.isImportCandidateIncluded(candidate.id) {
            return "checkmark.circle.fill"
        }
        if candidate.classification == .exactDuplicate {
            return "minus.circle"
        }
        if !candidate.isEligible {
            return "xmark.circle"
        }
        return "circle"
    }

    private var inclusionHelp: String {
        if candidate.classification == .exactDuplicate {
            return "Already in Library"
        }
        if !candidate.isEligible {
            return "This file cannot be imported"
        }
        return model.isImportCandidateIncluded(candidate.id)
            ? "Exclude \(candidate.title)"
            : "Include \(candidate.title)"
    }

    private var accessibilityLabel: String {
        "\(candidate.title), \(candidate.artist), \(candidate.album)"
    }

    private var accessibilityValue: String {
        let inclusion = model.isImportCandidateIncluded(candidate.id)
            ? "Included"
            : "Excluded"
        return "\(candidate.classification.title), \(inclusion)"
    }
}

private func currentImportSelectionIntent() -> ImportCandidateSelectionIntent {
    let modifiers = NSEvent.modifierFlags
    if modifiers.contains(.shift) {
        return .range
    }
    if modifiers.contains(.command) {
        return .toggle
    }
    return .replace
}
