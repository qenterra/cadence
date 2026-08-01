@testable import Cadence
import Foundation
import Testing

@MainActor
struct GuideCoordinatorTests {
    @Test("Welcome remains pending until the user chooses an outcome")
    func welcomeCompletion() {
        let store = InMemoryGuideProgressStore()
        let coordinator = GuideCoordinator(progressStore: store)

        coordinator.presentWelcomeIfNeeded()
        #expect(coordinator.presentation == .welcome)

        coordinator.dismissWelcomeWithoutCompleting()
        #expect(coordinator.presentation == .hidden)
        #expect(store.completedOnboardingVersion == 0)

        coordinator.presentWelcomeIfNeeded()
        coordinator.completeWelcome(startTour: false)
        #expect(coordinator.presentation == .hidden)
        #expect(
            store.completedOnboardingVersion
                == GuideCatalog.onboardingVersion
        )

        coordinator.presentWelcomeIfNeeded()
        #expect(coordinator.presentation == .hidden)
    }

    @Test("Starting the first-run tour completes onboarding")
    func welcomeStartsTour() {
        let store = InMemoryGuideProgressStore()
        let coordinator = GuideCoordinator(progressStore: store)

        coordinator.presentWelcomeIfNeeded()
        coordinator.completeWelcome(startTour: true)

        #expect(
            coordinator.presentation
                == .tour(chapterID: .essentials, stepIndex: 0)
        )
        #expect(coordinator.currentStep?.id == "essentials.sidebar")
        #expect(coordinator.progressText == "1 of 9")
        #expect(
            store.completedOnboardingVersion
                == GuideCatalog.onboardingVersion
        )
    }

    @Test("Tour navigation is bounded and finishes after the final step")
    func tourNavigation() {
        let coordinator = GuideCoordinator(
            progressStore: InMemoryGuideProgressStore(
                completedOnboardingVersion: GuideCatalog.onboardingVersion
            )
        )
        coordinator.start(.libraryAndImport)
        let chapter = GuideCatalog.chapter(.libraryAndImport)

        #expect(!coordinator.canGoBack)
        coordinator.goBack()
        #expect(coordinator.currentStepIndex == 0)

        coordinator.advance()
        #expect(coordinator.currentStepIndex == 1)
        #expect(coordinator.canGoBack)
        coordinator.goBack()
        #expect(coordinator.currentStepIndex == 0)

        for _ in chapter.steps.indices {
            coordinator.advance()
        }
        #expect(coordinator.presentation == .hidden)
        #expect(coordinator.currentStep == nil)
    }

    @Test("Chapter picker can be replaced by a focused chapter")
    func chapterPicker() {
        let coordinator = GuideCoordinator(
            progressStore: InMemoryGuideProgressStore()
        )

        coordinator.presentChapterPicker()
        #expect(coordinator.isChapterPickerPresented)

        coordinator.start(.playlists)
        #expect(coordinator.currentChapter?.id == .playlists)
        #expect(coordinator.currentStep?.id == "playlists.overview")

        coordinator.skip()
        #expect(coordinator.presentation == .hidden)
    }

    @Test("Guide catalog has stable unique and complete steps")
    func catalogIntegrity() {
        let chapters = GuideCatalog.allChapters
        let steps = chapters.flatMap(\.steps)

        #expect(chapters.map(\.id) == GuideChapterID.allCases)
        #expect(GuideCatalog.essentials.steps.count == 9)
        #expect(chapters.allSatisfy { !$0.steps.isEmpty })
        #expect(Set(steps.map(\.id)).count == steps.count)
        #expect(
            steps.allSatisfy {
                !$0.title.isEmpty && !$0.message.isEmpty
            }
        )
    }

    @Test("Unavailable targets use explicit fallback copy")
    func unavailableAnchorFallback() throws {
        let step = try #require(
            GuideCatalog.playbackAndLyrics.steps.first {
                $0.anchor == .lyrics
            }
        )

        #expect(step.displayedMessage(hasResolvedAnchor: true) == step.message)
        #expect(
            step.displayedMessage(hasResolvedAnchor: false)
                == step.unavailableMessage
        )
    }

    @Test("UserDefaults completion survives a coordinator restart")
    func userDefaultsPersistence() throws {
        let suiteName = "CadenceGuideTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let first = GuideCoordinator(
            progressStore: UserDefaultsGuideProgressStore(
                defaults: defaults
            )
        )
        first.presentWelcomeIfNeeded()
        first.completeWelcome(startTour: false)

        let second = GuideCoordinator(
            progressStore: UserDefaultsGuideProgressStore(
                defaults: defaults
            )
        )
        second.presentWelcomeIfNeeded()

        #expect(second.presentation == .hidden)
    }

    @Test("Guide routes reuse app navigation without changing library data")
    func routesReuseAppNavigation() {
        let model = CadenceAppModel.testFixture()
        let trackIDs = model.tracks.map(\.id)
        let tagAssignments = model.tagAssignments

        GuideRoute.destination(.tags).apply(to: model)
        #expect(model.selectedDestination == .tags)

        GuideRoute.nowPlaying(.queue).apply(to: model)
        #expect(model.playbackWorkspace == .nowPlaying)
        #expect(model.selectedNowPlayingPanel == .queue)

        GuideRoute.lyricsEditor.apply(to: model)
        #expect(model.playbackWorkspace == .lyricsEditor)
        #expect(model.tracks.map(\.id) == trackIDs)
        #expect(model.tagAssignments == tagAssignments)
    }
}
