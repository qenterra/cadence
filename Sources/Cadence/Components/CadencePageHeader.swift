import SwiftUI

struct CadencePageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    let guideAnchor: GuideAnchor?
    @ViewBuilder let actions: Actions

    init(
        _ title: String,
        subtitle: String? = nil,
        guideAnchor: GuideAnchor? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.guideAnchor = guideAnchor
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.bold())
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .guideAnchor(guideAnchor)

            Spacer(minLength: 24)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension CadencePageHeader where Actions == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil,
        guideAnchor: GuideAnchor? = nil
    ) {
        self.init(
            title,
            subtitle: subtitle,
            guideAnchor: guideAnchor
        ) {
            EmptyView()
        }
    }
}
