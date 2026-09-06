import AppKit
import QenTerraComponents
import SwiftUI

struct SettingsAboutSection: View {
    private let configuration: AboutPageConfiguration

    init(bundle: Bundle = .main) {
        configuration = CadenceAboutConfiguration.make(bundle: bundle)
    }

    var body: some View {
        AboutPage(
            configuration: configuration,
            presentation: .cadenceSettings
        ) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
        }
    }
}
