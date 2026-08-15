import AppKit
import SwiftUI

/// Places the application shell inside the unobscured region reported by the
/// host window while allowing its background to continue beneath native chrome.
struct WindowContentLayout<Content: View>: View {
    @State private var placement = WindowContentLayoutMetrics.Placement.identity

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            content
                .frame(
                    width: placement.size?.width ?? geometry.size.width,
                    height: placement.size?.height ?? geometry.size.height
                )
                .offset(
                    x: placement.offset.width,
                    y: placement.offset.height
                )
        }
        .background {
            WindowContentLayoutProbe { updatedPlacement in
                placement = updatedPlacement
            }
        }
    }
}

enum WindowContentLayoutMetrics {
    struct Placement: Equatable {
        let offset: CGSize
        let size: CGSize?

        static let identity = Placement(offset: .zero, size: nil)
    }

    static func placement(
        containerRect: CGRect,
        contentLayoutRect: CGRect
    ) -> Placement {
        Placement(
            offset: CGSize(
                width: max(
                    0,
                    contentLayoutRect.minX - containerRect.minX
                ),
                height: max(
                    0,
                    contentLayoutRect.minY - containerRect.minY
                )
            ),
            size: CGSize(
                width: min(containerRect.width, contentLayoutRect.width),
                height: min(containerRect.height, contentLayoutRect.height)
            )
        )
    }
}

private struct WindowContentLayoutProbe: NSViewRepresentable {
    let onChange: @MainActor (WindowContentLayoutMetrics.Placement) -> Void

    func makeNSView(context _: Context) -> ProbeView {
        ProbeView(onChange: onChange)
    }

    func updateNSView(_ nsView: ProbeView, context _: Context) {
        nsView.onChange = onChange
    }

    @MainActor
    final class ProbeView: NSView {
        var onChange: @MainActor (WindowContentLayoutMetrics.Placement) -> Void

        private var lastPlacement: WindowContentLayoutMetrics.Placement?
        private weak var observedWindow: NSWindow?

        init(
            onChange: @escaping @MainActor (
                WindowContentLayoutMetrics.Placement
            ) -> Void
        ) {
            self.onChange = onChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observeWindowGeometry()
            publishPlacement()
        }

        override func layout() {
            super.layout()
            publishPlacement()
        }

        @objc private func windowGeometryDidChange(_: Notification) {
            publishPlacement()
        }

        private func observeWindowGeometry() {
            guard let window, observedWindow == nil else {
                return
            }
            // A root hosting view remains attached to one scene window for its
            // lifetime. Keeping that identity avoids duplicate notifications.
            observedWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowGeometryDidChange(_:)),
                name: NSWindow.didResizeNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowGeometryDidChange(_:)),
                name: NSWindow.didUpdateNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowGeometryDidChange(_:)),
                name: NSWindow.didChangeScreenNotification,
                object: window
            )
        }

        private func publishPlacement() {
            guard
                let window,
                let contentView = window.contentView
            else {
                return
            }
            let layoutRect = contentView.convert(
                window.contentLayoutRect,
                from: nil
            )
            let containerRect = contentView.convert(bounds, from: self)
            publish(
                WindowContentLayoutMetrics.placement(
                    containerRect: containerRect,
                    contentLayoutRect: layoutRect
                )
            )
        }

        private func publish(
            _ placement: WindowContentLayoutMetrics.Placement
        ) {
            guard lastPlacement != placement else {
                return
            }
            lastPlacement = placement
            onChange(placement)
        }
    }
}
