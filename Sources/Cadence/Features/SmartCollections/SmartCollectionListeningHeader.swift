import SwiftUI

struct SmartCollectionListeningHeader: View {
    @Bindable var model: CadenceAppModel

    @State private var isRuleInfoPresented = false

    var body: some View {
        if let collection = model.selectedSmartCollection {
            HStack(alignment: .bottom, spacing: 24) {
                SmartCollectionArtworkMosaic(
                    model: model,
                    layout: model.selectedSmartCollectionArtwork,
                    title: collection.name
                )
                .frame(width: 168)

                VStack(alignment: .leading, spacing: 0) {
                    Text("SMART COLLECTION")
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.tertiary)

                    Text(collection.name)
                        .font(.system(size: 30, weight: .bold))
                        .lineLimit(2)
                        .padding(.top, 6)

                    Text(metadata)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.top, 7)

                    controls
                        .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 28)
            .padding(.top, 26)
            .padding(.bottom, 24)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                if isProduction {
                    model.playSelectedProductionSmartCollection()
                } else {
                    model.playSelectedSmartCollection()
                }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .frame(minWidth: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .disabled(selectedTracksAreEmpty)
            .keyboardShortcut(.return, modifiers: [.command])

            Button {
                if isProduction {
                    model.playSelectedProductionSmartCollection(
                        shuffled: true
                    )
                } else {
                    model.shuffleSelectedSmartCollection()
                }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .buttonStyle(.bordered)
            .disabled(selectedTracksAreEmpty)

            Button {
                isRuleInfoPresented.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.bordered)
            .help("Show collection rules")
            .accessibilityLabel("Show collection rules")
            .popover(isPresented: $isRuleInfoPresented, arrowEdge: .bottom) {
                if let collection = model.selectedSmartCollection {
                    SmartCollectionRuleInfoPopover(
                        collection: collection,
                        tags: model.tags
                    )
                }
            }

            Spacer(minLength: 8)

            Button("Edit Rules", systemImage: "slider.horizontal.3") {
                model.requestEditSelectedSmartCollection()
            }
            .buttonStyle(.bordered)

            collectionMenu
        }
        .controlSize(.regular)
    }

    private var collectionMenu: some View {
        Menu {
            if let collectionID = model.selectedSmartCollectionID {
                Button("Rename", systemImage: "pencil") {
                    model.requestRenameSmartCollection(collectionID)
                }

                Divider()

                Button("Delete", systemImage: "trash", role: .destructive) {
                    model.requestDeleteSmartCollection(collectionID)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30)
        .help("More collection actions")
        .accessibilityLabel("More collection actions")
    }

    private var metadata: String {
        let count = isProduction
            ? model.selectedProductionSmartCollectionTracks.count
            : model.selectedSmartCollectionCanonicalTracks.count
        let trackText = "\(count) \(count == 1 ? "track" : "tracks")"
        return "\(trackText) · \(durationText) · Updated automatically"
    }

    private var durationText: String {
        let duration = isProduction
            ? model.selectedProductionSmartCollectionTracks.reduce(0) {
                $0 + $1.duration
            }
            : model.selectedSmartCollectionDuration
        let totalMinutes = max(
            Int(duration.rounded()) / 60,
            0
        )
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours) hr \(minutes) min"
        }
        if hours > 0 {
            return "\(hours) hr"
        }
        return "\(minutes) min"
    }

    private var isProduction: Bool {
        model.librarySession.availability != .preview
    }

    private var selectedTracksAreEmpty: Bool {
        if isProduction {
            return model.selectedProductionSmartCollectionTracks.isEmpty
        }
        return model.selectedSmartCollectionCanonicalTracks.isEmpty
    }
}
