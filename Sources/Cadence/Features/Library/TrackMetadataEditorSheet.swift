import SwiftUI

struct TrackMetadataEditorSheet: View {
    @Bindable var model: CadenceAppModel
    let presentation: TrackMetadataEditPresentation

    @State private var title: String
    @State private var artist: String
    @State private var album: String
    @State private var year: String
    @State private var isSaving = false

    init(
        model: CadenceAppModel,
        presentation: TrackMetadataEditPresentation
    ) {
        self.model = model
        self.presentation = presentation
        _title = State(initialValue: presentation.title)
        _artist = State(initialValue: presentation.artist)
        _album = State(initialValue: presentation.album)
        _year = State(
            initialValue: presentation.year.map(String.init) ?? ""
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            fields
                .padding(24)
            Divider()
            footer
        }
        .frame(width: 520)
        .background(CadenceTheme.opaqueSurface)
        .interactiveDismissDisabled(isSaving)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(CadenceTheme.primaryAccent)
                .frame(width: 36, height: 36)
                .background(CadenceTheme.subduedFill, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Information")
                    .font(.headline)
                Text("Changes are written to the managed audio file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }

    private var fields: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
            metadataField("Track", text: $title)
            metadataField("Artist", text: $artist)
            metadataField("Album", text: $album)
            GridRow {
                Text("Year")
                    .foregroundStyle(.secondary)
                TextField("Optional", text: $year)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var footer: some View {
        HStack {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                Text("Writing tags…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") {
                model.dismissTrackMetadataEditor()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving)
            Button("Save") {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .cadenceActionTint(.confirmation)
            .disabled(!canSave || isSaving)
        }
        .padding(20)
        .background(CadenceTheme.secondarySurface)
    }

    private func metadataField(
        _ label: LocalizedStringKey,
        text: Binding<String>
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
        }
    }

    private var parsedYear: Int? {
        let value = year.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : Int(value)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (year.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || parsedYear.map { (0 ... 9999).contains($0) } == true)
    }

    private func save() {
        guard canSave else {
            return
        }
        isSaving = true
        Task {
            let saved = await model.saveTrackMetadata(
                ManagedAudioMetadataEdit(
                    title: title,
                    artist: artist,
                    album: album,
                    year: parsedYear
                ),
                for: presentation
            )
            if !saved {
                isSaving = false
            }
        }
    }
}
