import AppKit
import SwiftUI

struct CadenceWelcomeView: View {
    @Bindable var coordinator: GuideCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageIndex = 0

    private let pages = WelcomePage.all

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 26)

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 104, height: 104)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(pages[pageIndex].title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(pages[pageIndex].message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 500)
            }
            .id(pageIndex)
            .transition(.opacity)
            .frame(maxHeight: .infinity)

            pageIndicator

            controls
                .padding(.top, 24)
        }
        .padding(36)
        .frame(width: 700, height: 520)
        .background(CadenceTheme.contentBackground)
        .animation(
            reduceMotion ? nil : .easeOut(duration: CadenceTheme.motionDismiss),
            value: pageIndex
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("Cadence.Welcome")
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(
                        index == pageIndex
                            ? CadenceTheme.primaryAccent
                            : CadenceTheme.strongSeparator
                    )
                    .frame(
                        width: index == pageIndex ? 20 : 7,
                        height: 7
                    )
                    .accessibilityHidden(true)
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: CadenceTheme.motionPresent),
            value: pageIndex
        )
    }

    @ViewBuilder
    private var controls: some View {
        if pageIndex == pages.count - 1 {
            HStack(spacing: 12) {
                Button("Explore on My Own") {
                    coordinator.completeWelcome(startTour: false)
                }
                .accessibilityIdentifier("Cadence.Welcome.Explore")

                Button("Start Tour") {
                    coordinator.completeWelcome(startTour: true)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("Cadence.Welcome.StartTour")
            }
        } else {
            HStack {
                if pageIndex > 0 {
                    Button("Back") {
                        pageIndex -= 1
                    }
                }

                Spacer()

                Button("Continue") {
                    pageIndex += 1
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("Cadence.Welcome.Continue")
            }
        }
    }
}

private struct WelcomePage {
    let title: String
    let message: String

    static let all = [
        WelcomePage(
            title: "Welcome to Cadence",
            message: "A focused home for the music you already own — "
                + "built for listening, exploring, and making the library yours."
        ),
        WelcomePage(
            title: "Your Music Stays Yours",
            message: "Cadence preserves every original. Approved imports are "
                + "copied into ~/Music/Cadence.library under stable track IDs."
        ),
        WelcomePage(
            title: "Make the Library Your Own",
            message: "Use tags, Smart Collections, playlists, artwork, and "
                + "line-timed lyrics without rewriting your source files."
        ),
    ]
}
