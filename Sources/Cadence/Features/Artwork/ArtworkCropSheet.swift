import AppKit
import SwiftUI

struct ArtworkCropSheet: View {
    let draft: ArtworkCropDraft
    let cancel: () -> Void
    let save: (CGFloat, CGSize) -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    private let previewSize: CGFloat = 340

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 5) {
                Text(sheetTitle)
                    .font(.title2.bold())
                Text(instruction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            cropPreview

            HStack(spacing: 12) {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)

                Slider(value: $scale, in: 1 ... 4)
                    .accessibilityLabel("Image Zoom")

                Image(systemName: "photo.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: previewSize)

            HStack {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    save(
                        scale,
                        CGSize(
                            width: offset.width / previewSize,
                            height: offset.height / previewSize
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
        }
        .padding(24)
        .frame(width: 500)
        .background(CadenceTheme.opaqueSurface)
        .onChange(of: scale) {
            offset = clamped(offset)
        }
    }

    private var cropPreview: some View {
        Group {
            if let image = NSImage(data: draft.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: previewSize, height: previewSize)
                    .scaleEffect(scale)
                    .offset(x: liveOffset.width, y: liveOffset.height)
            } else {
                ContentUnavailableView(
                    "Image Unavailable",
                    systemImage: "photo.badge.exclamationmark"
                )
            }
        }
        .frame(width: previewSize, height: previewSize)
        .clipShape(cropShape)
        .overlay {
            cropShape
                .stroke(.white.opacity(0.32), lineWidth: 1)
        }
        .background {
            cropShape
                .fill(CadenceTheme.secondarySurface)
        }
        .contentShape(cropShape)
        .gesture(dragGesture)
        .accessibilityLabel("\(shapeName) crop preview for \(draft.title)")
    }

    private var cropShape: AnyShape {
        switch draft.shape {
        case .circle:
            AnyShape(Circle())
        case .square:
            AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var liveOffset: CGSize {
        clamped(
            CGSize(
                width: offset.width + dragTranslation.width,
                height: offset.height + dragTranslation.height
            )
        )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                offset = clamped(
                    CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    )
                )
            }
    }

    private func clamped(_ proposedOffset: CGSize) -> CGSize {
        ArtworkCropGeometry(
            previewSize: previewSize,
            sourceSize: NSImage(data: draft.data)?.size ?? .zero
        )
        .clamped(
            proposedOffset,
            scale: scale
        )
    }

    private var sheetTitle: String {
        switch draft.target {
        case .artist, .managedArtist:
            "Artist Image"
        case .album, .managedAlbum:
            "Album Artwork"
        case .track, .managedTrack:
            "Track Artwork"
        }
    }

    private var instruction: String {
        "Position \(draft.title) inside the \(shapeName.lowercased()) crop."
    }

    private var shapeName: String {
        draft.shape == .circle ? "Circular" : "Square"
    }
}
