import SwiftUI

struct SmartCollectionRuleInfoPopover: View {
    let collection: SmartCollectionPreview
    let tagTitlesByID: [String: String]

    private var rows: [SmartCollectionRuleSummaryRow] {
        SmartCollectionRuleSummary.rows(
            for: collection.rule,
            tagTitlesByID: tagTitlesByID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Collection Rules")
                    .font(.headline)

                Text("Read-only summary")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(
                                systemName: row.kind == .group
                                    ? "arrow.triangle.branch"
                                    : "line.3.horizontal.decrease"
                            )
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 14)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.text)
                                    .font(
                                        row.kind == .group
                                            ? .callout.weight(.medium)
                                            : .callout
                                    )
                                    .foregroundStyle(.primary)

                                if let detail = row.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.leading, CGFloat(row.depth) * 14)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 360, height: min(CGFloat(150 + rows.count * 48), 440))
        .background(CadenceTheme.secondarySurface)
    }
}
