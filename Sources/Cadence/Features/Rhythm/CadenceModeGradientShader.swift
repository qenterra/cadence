import Foundation

enum CadenceModeGradientShader {
    static let source: String? = {
        guard let url = Bundle.main.url(
            forResource: "CadenceModeGradientShader",
            withExtension: "metal.txt"
        ) else {
            return nil
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
}
