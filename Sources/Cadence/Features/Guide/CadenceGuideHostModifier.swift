import SwiftUI

struct CadenceGuideHostModifier: ViewModifier {
    @Bindable var model: CadenceAppModel
    @Bindable var coordinator: GuideCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: welcomeBinding) {
                CadenceWelcomeView(coordinator: coordinator)
            }
            .sheet(isPresented: chapterPickerBinding) {
                GuideChapterPickerView(coordinator: coordinator)
            }
            .overlayPreferenceValue(
                GuideAnchorPreferenceKey.self
            ) { anchors in
                if coordinator.isTourPresented {
                    CadenceGuideOverlay(
                        coordinator: coordinator,
                        anchors: anchors
                    )
                    .zIndex(100)
                }
            }
            .onChange(
                of: coordinator.currentStep?.id,
                initial: true
            ) {
                applyCurrentRoute()
            }
    }

    private var welcomeBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isWelcomePresented },
            set: { isPresented in
                if !isPresented {
                    coordinator.dismissWelcomeWithoutCompleting()
                }
            }
        )
    }

    private var chapterPickerBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isChapterPickerPresented },
            set: { isPresented in
                if !isPresented {
                    coordinator.dismissChapterPicker()
                }
            }
        )
    }

    private func applyCurrentRoute() {
        guard let route = coordinator.currentStep?.route else {
            return
        }
        route.apply(to: model)
    }
}

@MainActor
extension GuideRoute {
    func apply(to model: CadenceAppModel) {
        switch self {
        case let .destination(destination):
            model.requestNavigationDestination(destination)
        case let .nowPlaying(panel):
            let didPresent = switch panel {
            case .lyrics:
                model.presentNowPlaying()
            case .queue:
                model.presentPlaybackQueue()
            }
            if didPresent {
                model.selectNowPlayingPanel(panel)
            }
        case .lyricsEditor:
            model.presentLyricsEditor()
        }
    }
}

extension View {
    func cadenceGuideHost(
        model: CadenceAppModel,
        coordinator: GuideCoordinator
    ) -> some View {
        modifier(
            CadenceGuideHostModifier(
                model: model,
                coordinator: coordinator
            )
        )
    }
}
