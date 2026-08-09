import AppKit
import SwiftUI

@MainActor
final class TrackTableView: NSTableView {
    var onReturn: (() -> Void)?
    var onSpace: (() -> Void)?
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36:
            onReturn?()
        case 49:
            onSpace?()
        case 51, 117:
            onDelete?()
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class TrackTableHostingCell: NSTableCellView {
    private let hostingView = NSHostingView(
        rootView: AnyView(EmptyView())
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    func setRootView(_ rootView: AnyView) {
        hostingView.rootView = rootView
    }
}

struct TrackTablePlaceholderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(
                cornerRadius: CadenceTheme.radiusControl,
                style: .continuous
            )
            .fill(CadenceTheme.subduedFill)
            .frame(width: 40, height: 40)
            RoundedRectangle(
                cornerRadius: CadenceTheme.radiusControl,
                style: .continuous
            )
            .fill(CadenceTheme.subduedFill)
            .frame(width: 180)
            .frame(height: 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .redacted(reason: .placeholder)
    }
}
