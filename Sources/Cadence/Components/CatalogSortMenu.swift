import SwiftUI

enum CatalogSortDirection: String, CaseIterable, Hashable, Sendable {
    case ascending
    case descending

    var title: String {
        switch self {
        case .ascending: String(localized: "Ascending")
        case .descending: String(localized: "Descending")
        }
    }
}

struct CatalogSortSelection<Field: Hashable & Sendable>: Equatable, Sendable {
    private(set) var field: Field
    private(set) var direction: CatalogSortDirection

    mutating func select(field: Field) {
        self.field = field
    }

    mutating func select(direction: CatalogSortDirection) {
        self.direction = direction
    }
}

struct CatalogSortMenu<Field: Identifiable & Hashable & Sendable>: View {
    let label: LocalizedStringKey
    let fields: [Field]
    @Binding var selection: CatalogSortSelection<Field>
    let fieldTitle: (Field) -> String

    var body: some View {
        Menu {
            ForEach(fields) { field in
                Button {
                    var next = selection
                    next.select(field: field)
                    selection = next
                } label: {
                    choiceLabel(
                        fieldTitle(field),
                        isSelected: selection.field == field
                    )
                }
            }

            Divider()

            ForEach(CatalogSortDirection.allCases, id: \.self) { direction in
                Button {
                    var next = selection
                    next.select(direction: direction)
                    selection = next
                } label: {
                    choiceLabel(
                        direction.title,
                        isSelected: selection.direction == direction
                    )
                }
            }
        } label: {
            Label {
                HStack(spacing: 0) {
                    Text(label)
                    Text(
                        verbatim: ": \(fieldTitle(selection.field))"
                    )
                }
            } icon: {
                Image(systemName: "arrow.up.arrow.down.circle")
            }
        }
        .menuStyle(.borderlessButton)
    }

    private func choiceLabel(
        _ title: String,
        isSelected: Bool
    ) -> some View {
        HStack {
            Text(title)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }
}
