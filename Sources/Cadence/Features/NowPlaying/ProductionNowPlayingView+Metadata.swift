import SwiftUI

extension ProductionNowPlayingView {
    var trackTags: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .frame(height: 24)

                    CadenceFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                        ForEach(tagStates.prefix(3)) { state in
                            Button {
                                model.requestOpenProductionTagContextually(
                                    id: state.tag.id
                                )
                            } label: {
                                Text(state.tag.displayPath)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(
                                        CadenceTheme.subduedFill,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Show tracks tagged " + state.tag.displayPath)
                        }

                        if tagStates.count > 3 {
                            Text("+\(tagStates.count - 3)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(height: 24)
                        }

                        TextField("Add a tag", text: $newTagPath)
                            .textFieldStyle(.plain)
                            .font(.caption)
                            .frame(width: 110, height: 24)
                            .onSubmit(addTag)
                            .disabled(isAddingTag)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !trimmedTagPath.isEmpty {
                        Button(action: addTag) {
                            Image(systemName: "plus")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(isAddingTag)
                        .help("Assign Tag")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 36)
                .background(
                    CadenceTheme.subduedFill,
                    in: RoundedRectangle(
                        cornerRadius: CadenceTheme.radiusControl,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: CadenceTheme.radiusControl,
                        style: .continuous
                    )
                    .strokeBorder(CadenceTheme.separator, lineWidth: 0.5)
                }

                Button {
                    model.openProductionTagEditor(trackID: track.id)
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 34, height: 34)
                        .background(
                            CadenceTheme.subduedFill,
                            in: RoundedRectangle(
                                cornerRadius: CadenceTheme.radiusControl,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
                .help("Edit Tags")
                .accessibilityLabel("Edit Tags for \(displayedTrackTitle)")
            }

            if let tagError {
                Text(tagError)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var externalFileNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Playing external file", systemImage: "doc.badge.play")
                .font(.caption.weight(.semibold))
            Text("This track is not in your library. Add it only if you want to keep it there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            CadenceTheme.subduedFill,
            in: RoundedRectangle(
                cornerRadius: CadenceTheme.radiusControl,
                style: .continuous
            )
        )
    }

    var trimmedTagPath: String {
        newTagPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func addTag() {
        let path = trimmedTagPath
        guard !path.isEmpty else {
            return
        }
        Task { @MainActor in
            isAddingTag = true
            defer { isAddingTag = false }
            do {
                _ = try await model.librarySession.store.createTagAndAssign(
                    displayPath: path,
                    trackID: track.id
                )
                newTagPath = ""
                tagError = nil
                tagStates = try await model.librarySession.store.tagStates(
                    trackID: track.id
                )
            } catch {
                tagError = error.localizedDescription
            }
        }
    }
}
