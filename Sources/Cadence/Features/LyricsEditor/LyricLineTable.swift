import AppKit
import SwiftUI

struct LyricLineTable: View {
    @Bindable var model: CadenceAppModel

    @Environment(\.undoManager) private var undoManager
    @State private var exportPreview: String?
    @State private var importFailed = false

    var body: some View {
        VStack(spacing: 0) {
            tableToolbar

            Rectangle()
                .fill(CadenceTheme.separator)
                .frame(height: 1)

            tableHeader

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        if let draft = model.lyricDraft {
                            ForEach(
                                Array(draft.lines.enumerated()),
                                id: \.element.id
                            ) { index, line in
                                LyricLineEditorRow(
                                    model: model,
                                    line: line,
                                    displayIndex: index + 1,
                                    issue: issue(for: line.id)
                                )
                                .id(line.id)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .onChange(of: model.lyricDraft?.activeLineID) {
                    guard let activeLineID = model.lyricDraft?.activeLineID else {
                        return
                    }
                    proxy.scrollTo(activeLineID, anchor: .center)
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { exportPreview != nil },
                set: { isPresented in
                    if !isPresented {
                        exportPreview = nil
                    }
                }
            )
        ) {
            LyricsExportPreview(source: exportPreview ?? "")
        }
        .alert(
            "LRC Could Not Be Imported",
            isPresented: $importFailed
        ) {
            Button("OK") {}
        } message: {
            Text("The clipboard does not contain a valid line-level LRC document.")
        }
    }

    private var tableToolbar: some View {
        HStack(spacing: 10) {
            Button("Add Line", systemImage: "plus") {
                model.addLyricLine(
                    after: model.lyricDraft?.activeLineID,
                    undoManager: undoManager
                )
            }

            Button("Paste Text", systemImage: "doc.on.clipboard") {
                guard
                    let source = NSPasteboard.general.string(
                        forType: .string
                    ),
                    !source.isEmpty
                else {
                    return
                }
                model.replaceLyricDraftWithPlainText(
                    source,
                    undoManager: undoManager
                )
            }

            Menu("LRC") {
                Button("Import from Clipboard") {
                    guard
                        let source = NSPasteboard.general.string(
                            forType: .string
                        )
                    else {
                        importFailed = true
                        return
                    }
                    importFailed = !model.replaceLyricDraftWithLRC(
                        source,
                        undoManager: undoManager
                    )
                }

                Button("Export Preview") {
                    guard
                        let document = model.lyricDraft?.document,
                        let source = try? LineLevelLRC.generate(document)
                    else {
                        return
                    }
                    exportPreview = source
                }
                .disabled(
                    model.lyricDraft?.document.timingStatus
                        == .missing
                )

                Button("Copy LRC") {
                    guard
                        let document = model.lyricDraft?.document,
                        let source = try? LineLevelLRC.generate(document)
                    else {
                        return
                    }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        source,
                        forType: .string
                    )
                }
                .disabled(
                    model.lyricDraft?.document.timingStatus
                        == .missing
                )
            }

            Spacer()

            Button("Clear Timing", systemImage: "clock.badge.xmark") {
                model.clearLyricTimestamps(undoManager: undoManager)
            }
            .disabled(
                model.lyricDraft?.lines.contains {
                    $0.startTime != nil
                } != true
            )
        }
        .controlSize(.small)
        .padding(.horizontal, 18)
        .frame(height: 50)
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Text("#")
                .frame(width: 32, alignment: .trailing)
            Text("Time")
                .frame(width: 88, alignment: .leading)
            Text("Lyric")
            Spacer()
            Text("Order")
                .frame(width: 74, alignment: .center)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 24)
        .frame(height: 34)
    }

    private func issue(
        for lineID: LyricLine.ID
    ) -> LyricValidationIssue? {
        model.lyricDraftValidationIssues.first {
            $0.lineID == lineID
        }
    }
}

private struct LyricLineEditorRow: View {
    @Bindable var model: CadenceAppModel

    let line: LyricLine
    let displayIndex: Int
    let issue: LyricValidationIssue?

    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Button {
                    model.activateLyricLine(line.id)
                } label: {
                    Text(displayIndex.formatted())
                        .font(.caption)
                        .foregroundStyle(
                            isActive ? .primary : .tertiary
                        )
                        .monospacedDigit()
                        .frame(width: 32, alignment: .trailing)
                }
                .buttonStyle(.plain)

                LyricTimestampField(
                    value: line.startTime,
                    hasError: issue != nil
                ) { value in
                    model.updateLyricTimestamp(
                        lineID: line.id,
                        startTime: value,
                        undoManager: undoManager
                    )
                }
                .frame(width: 88)

                TextField(
                    "Lyric line",
                    text: Binding(
                        get: { line.text },
                        set: { text in
                            model.updateLyricText(
                                lineID: line.id,
                                text: text,
                                undoManager: undoManager
                            )
                        }
                    )
                )
                .textFieldStyle(.plain)
                .onTapGesture {
                    model.activateLyricLine(line.id)
                }

                HStack(spacing: 4) {
                    Button {
                        model.moveLyricLine(
                            line.id,
                            by: -1,
                            undoManager: undoManager
                        )
                    } label: {
                        Image(systemName: "chevron.up")
                    }

                    Button {
                        model.moveLyricLine(
                            line.id,
                            by: 1,
                            undoManager: undoManager
                        )
                    } label: {
                        Image(systemName: "chevron.down")
                    }

                    Button(role: .destructive) {
                        model.removeLyricLine(
                            line.id,
                            undoManager: undoManager
                        )
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .buttonStyle(.borderless)
                .frame(width: 92)
            }

            if let issue {
                Text(issue.message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.leading, 134)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, issue == nil ? 8 : 6)
        .background(
            isActive
                ? CadenceTheme.selectionFill
                : Color.clear,
            in: RoundedRectangle(cornerRadius: CadenceTheme.radiusControl, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.activateLyricLine(line.id)
        }
        .accessibilityValue(isActive ? "Active line" : "")
    }

    private var isActive: Bool {
        model.lyricDraft?.activeLineID == line.id
    }
}

private struct LyricTimestampField: View {
    let value: TimeInterval?
    let hasError: Bool
    let onCommit: (TimeInterval?) -> Void

    @FocusState private var isFocused: Bool
    @State private var text: String

    init(
        value: TimeInterval?,
        hasError: Bool,
        onCommit: @escaping (TimeInterval?) -> Void
    ) {
        self.value = value
        self.hasError = hasError
        self.onCommit = onCommit
        _text = State(initialValue: value.map(LyricTimestampFormatter.display) ?? "")
    }

    var body: some View {
        TextField("—", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.caption.monospacedDigit())
            .focused($isFocused)
            .overlay {
                if hasError {
                    RoundedRectangle(cornerRadius: CadenceTheme.radiusControl)
                        .strokeBorder(.red, lineWidth: 1)
                }
            }
            .onSubmit {
                onCommit(Self.parse(text))
            }
            .onChange(of: isFocused) {
                if !isFocused {
                    onCommit(Self.parse(text))
                }
            }
            .onChange(of: value) {
                guard !isFocused else {
                    return
                }
                text = value.map(LyricTimestampFormatter.display) ?? ""
            }
    }

    private static func parse(_ source: String) -> TimeInterval? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let components = trimmed.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard
            components.count == 2,
            let minutes = Double(components[0]),
            let seconds = Double(components[1])
        else {
            return Double(trimmed)
        }
        return minutes * 60 + seconds
    }
}

private struct LyricsExportPreview: View {
    let source: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("LRC Export Preview")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Text(
                "Preview only. Real file writing arrives with local-library integration."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            TextEditor(text: .constant(source))
                .font(.body.monospaced())
                .frame(minWidth: 520, minHeight: 300)
        }
        .padding(20)
    }
}
