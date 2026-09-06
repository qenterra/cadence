import QenTerraComponents
import SwiftUI

struct CadencePageHeader<Actions: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let actions: Actions

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        PageHeader(
            title,
            subtitle: subtitle,
            presentation: .cadence
        ) {
            actions
        }
    }
}

extension CadencePageHeader where Actions == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil
    ) {
        self.init(
            title,
            subtitle: subtitle
        ) {
            EmptyView()
        }
    }
}
