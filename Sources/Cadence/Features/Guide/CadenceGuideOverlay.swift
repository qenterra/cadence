import SwiftUI

struct CadenceGuideOverlay: View {
    @Bindable var coordinator: GuideCoordinator
    let anchors: [GuideAnchor: Anchor<CGRect>]
    var keyboardNavigationEnabled = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        GeometryReader { geometry in
            if let step = coordinator.currentStep {
                let target = targetRect(for: step, in: geometry)

                ZStack {
                    dimmingLayer(size: geometry.size, target: target)

                    if let target {
                        targetHighlight(target)
                    }

                    GuideCard(
                        chapterTitle: coordinator.currentChapter?.id.title
                            ?? "Cadence Guide",
                        step: step,
                        message: step.displayedMessage(
                            hasResolvedAnchor: target != nil
                        ),
                        progress: coordinator.progressText,
                        canGoBack: coordinator.canGoBack,
                        isLastStep: coordinator.isLastStep,
                        goBack: coordinator.goBack,
                        skip: coordinator.skip,
                        advance: coordinator.advance
                    )
                    .frame(width: 370)
                    .frame(maxHeight: GuideOverlayLayout.cardSize.height)
                    .position(
                        GuideOverlayLayout.cardCenter(
                            viewportSize: geometry.size,
                            target: target,
                            placement: step.placement
                        )
                    )
                    .id(step.id)
                    .transition(.opacity)
                }
                .contentShape(Rectangle())
                .guideKeyboardNavigation(
                    enabled: keyboardNavigationEnabled,
                    stepID: step.id,
                    canGoBack: coordinator.canGoBack,
                    actions: GuideKeyboardActions(
                        goBack: coordinator.goBack,
                        skip: coordinator.skip,
                        advance: coordinator.advance
                    )
                )
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.16),
                    value: step.id
                )
                .accessibilityIdentifier("Cadence.Guide.Overlay")
            }
        }
        .ignoresSafeArea()
    }

    private func targetRect(
        for step: GuideStep,
        in geometry: GeometryProxy
    ) -> CGRect? {
        guard let anchor = anchors[step.anchor] else {
            return nil
        }
        return GuideOverlayLayout.spotlightRect(
            rawRect: geometry[anchor],
            viewportSize: geometry.size
        )
    }

    private func dimmingLayer(
        size: CGSize,
        target: CGRect?
    ) -> some View {
        var path = Path()
        path.addRect(CGRect(origin: .zero, size: size))
        if let target {
            path.addRoundedRect(
                in: target,
                cornerSize: CGSize(width: 13, height: 13)
            )
        }
        return path.fill(
            Color.black.opacity(reduceTransparency ? 0.64 : 0.48),
            style: FillStyle(eoFill: true)
        )
    }

    private func targetHighlight(_ target: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(
                CadenceTheme.primaryAccent.opacity(
                    contrast == .increased ? 1 : 0.82
                ),
                lineWidth: contrast == .increased ? 2 : 1.25
            )
            .shadow(
                color: CadenceTheme.primaryAccent.opacity(0.22),
                radius: 12
            )
            .frame(width: target.width, height: target.height)
            .position(x: target.midX, y: target.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func guideKeyboardNavigation(
        enabled: Bool,
        stepID: String,
        canGoBack: Bool,
        actions: GuideKeyboardActions
    ) -> some View {
        if enabled {
            modifier(
                GuideKeyboardNavigationModifier(
                    stepID: stepID,
                    canGoBack: canGoBack,
                    actions: actions
                )
            )
        } else {
            self
        }
    }
}

private struct GuideKeyboardActions {
    let goBack: () -> Void
    let skip: () -> Void
    let advance: () -> Void
}

private struct GuideKeyboardNavigationModifier: ViewModifier {
    let stepID: String
    let canGoBack: Bool
    let actions: GuideKeyboardActions

    @FocusState private var receivesKeyboardInput: Bool
    @AccessibilityFocusState private var cardHasAccessibilityFocus: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityFocused($cardHasAccessibilityFocus)
            .focusable()
            .focusEffectDisabled()
            .focused($receivesKeyboardInput)
            .onAppear(perform: claimFocus)
            .onChange(of: stepID) {
                claimFocus()
            }
            .onKeyPress(.escape, phases: .down) { _ in
                actions.skip()
                return .handled
            }
            .onKeyPress(.leftArrow, phases: .down) { _ in
                guard canGoBack else {
                    return .ignored
                }
                actions.goBack()
                return .handled
            }
            .onKeyPress(.rightArrow, phases: .down) { _ in
                actions.advance()
                return .handled
            }
    }

    private func claimFocus() {
        receivesKeyboardInput = true
        cardHasAccessibilityFocus = true
    }
}

private struct GuideCard: View {
    let chapterTitle: String
    let step: GuideStep
    let message: String
    let progress: String
    let canGoBack: Bool
    let isLastStep: Bool
    let goBack: () -> Void
    let skip: () -> Void
    let advance: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            cardContent
            ScrollView {
                cardContent
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: GuideOverlayLayout.cardSize.height)
        .background(
            CadenceTheme.opaqueSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(CadenceTheme.strongSeparator, lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(step.title). \(message). \(progress)"
        )
        .accessibilityIdentifier("Cadence.Guide.Card.\(step.id)")
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(chapterTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(progress)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(step.title)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if canGoBack {
                    Button("Back", action: goBack)
                }

                Button("Skip Tour", action: skip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(isLastStep ? "Done" : "Next", action: advance)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
