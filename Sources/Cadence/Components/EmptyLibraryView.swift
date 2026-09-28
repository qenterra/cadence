import QenTerraComponents
import SwiftUI

struct WindowCenteredContentStateLayout: Layout {
    static func center(in bounds: CGRect) -> CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews _: Subviews,
        cache _: inout ()
    ) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        let fullWorkspaceProposal = ProposedViewSize(
            width: bounds.width,
            height: bounds.height
        )

        for subview in subviews {
            subview.place(
                at: Self.center(in: bounds),
                anchor: .center,
                proposal: fullWorkspaceProposal
            )
        }
    }
}

struct WindowCenteredContentStatePage<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder header: () -> Header
    ) {
        self.content = content()
        self.header = header()
    }

    var body: some View {
        ZStack(alignment: .top) {
            WindowCenteredContentStateLayout {
                content
            }

            header
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension WindowCenteredContentStatePage where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content) {
            EmptyView()
        }
    }
}

struct EmptyLibraryView: View {
    let title: String
    let description: String
    let importAction: () -> Void

    var body: some View {
        ContentStateView(
            state: .empty(title: title, message: description),
            symbolName: "music.note",
            actions: [
                PresentationAction(
                    title: "Import Music",
                    style: .primary,
                    handler: importAction
                ),
            ],
            presentation: .nativeUnavailable
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
