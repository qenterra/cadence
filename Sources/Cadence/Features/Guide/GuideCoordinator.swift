import Foundation
import Observation

@MainActor
protocol GuideProgressStoring: AnyObject {
    var completedOnboardingVersion: Int { get set }
}

@MainActor
final class UserDefaultsGuideProgressStore: GuideProgressStoring {
    private enum Key {
        static let completedVersion = "guide.completedOnboardingVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var completedOnboardingVersion: Int {
        get { defaults.integer(forKey: Key.completedVersion) }
        set { defaults.set(newValue, forKey: Key.completedVersion) }
    }
}

@MainActor
final class InMemoryGuideProgressStore: GuideProgressStoring {
    var completedOnboardingVersion: Int

    init(completedOnboardingVersion: Int = 0) {
        self.completedOnboardingVersion = completedOnboardingVersion
    }
}

enum GuidePresentation: Equatable, Sendable {
    case hidden
    case welcome
    case chapterPicker
    case tour(chapterID: GuideChapterID, stepIndex: Int)
}

@MainActor
@Observable
final class GuideCoordinator {
    private let progressStore: any GuideProgressStoring

    private(set) var presentation: GuidePresentation = .hidden

    init(
        progressStore: any GuideProgressStoring =
            UserDefaultsGuideProgressStore()
    ) {
        self.progressStore = progressStore
    }

    var isWelcomePresented: Bool {
        presentation == .welcome
    }

    var isChapterPickerPresented: Bool {
        presentation == .chapterPicker
    }

    var isTourPresented: Bool {
        if case .tour = presentation {
            return true
        }
        return false
    }

    var currentChapter: GuideChapter? {
        guard case let .tour(chapterID, _) = presentation else {
            return nil
        }
        return GuideCatalog.chapter(chapterID)
    }

    var currentStepIndex: Int? {
        guard case let .tour(_, stepIndex) = presentation else {
            return nil
        }
        return stepIndex
    }

    var currentStep: GuideStep? {
        guard
            let currentChapter,
            let currentStepIndex,
            currentChapter.steps.indices.contains(currentStepIndex)
        else {
            return nil
        }
        return currentChapter.steps[currentStepIndex]
    }

    var progressText: String {
        guard let currentChapter, let currentStepIndex else {
            return ""
        }
        return "\(currentStepIndex + 1) of \(currentChapter.steps.count)"
    }

    var canGoBack: Bool {
        (currentStepIndex ?? 0) > 0
    }

    var isLastStep: Bool {
        guard let currentChapter, let currentStepIndex else {
            return false
        }
        return currentStepIndex == currentChapter.steps.count - 1
    }

    func presentWelcomeIfNeeded() {
        guard
            presentation == .hidden,
            progressStore.completedOnboardingVersion
            < GuideCatalog.onboardingVersion
        else {
            return
        }
        presentation = .welcome
    }

    func dismissWelcomeWithoutCompleting() {
        guard presentation == .welcome else {
            return
        }
        presentation = .hidden
    }

    func completeWelcome(startTour: Bool) {
        guard presentation == .welcome else {
            return
        }
        progressStore.completedOnboardingVersion =
            GuideCatalog.onboardingVersion
        if startTour {
            start(.essentials)
        } else {
            presentation = .hidden
        }
    }

    func presentChapterPicker() {
        presentation = .chapterPicker
    }

    func dismissChapterPicker() {
        guard presentation == .chapterPicker else {
            return
        }
        presentation = .hidden
    }

    func start(_ chapterID: GuideChapterID) {
        let chapter = GuideCatalog.chapter(chapterID)
        guard !chapter.steps.isEmpty else {
            presentation = .hidden
            return
        }
        presentation = .tour(chapterID: chapterID, stepIndex: 0)
    }

    func goBack() {
        guard
            case let .tour(chapterID, stepIndex) = presentation,
            stepIndex > 0
        else {
            return
        }
        presentation = .tour(
            chapterID: chapterID,
            stepIndex: stepIndex - 1
        )
    }

    func advance() {
        guard
            case let .tour(chapterID, stepIndex) = presentation
        else {
            return
        }
        let chapter = GuideCatalog.chapter(chapterID)
        let nextIndex = stepIndex + 1
        guard chapter.steps.indices.contains(nextIndex) else {
            presentation = .hidden
            return
        }
        presentation = .tour(
            chapterID: chapterID,
            stepIndex: nextIndex
        )
    }

    func skip() {
        guard isTourPresented else {
            return
        }
        presentation = .hidden
    }
}
