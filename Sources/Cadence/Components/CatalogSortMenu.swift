import QenTerraComponents
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
    let label: String
    let fields: [Field]
    @Binding var selection: CatalogSortSelection<Field>
    let fieldTitle: (Field) -> String

    var body: some View {
        SortMenu(
            fields: fields.map {
                SortMenuField(id: $0, title: fieldTitle($0))
            },
            selection: fieldBinding,
            order: orderBinding,
            labels: SortMenuLabels(
                trigger: label,
                field: String(localized: "Field"),
                order: String(localized: "Direction"),
                ascending: CatalogSortDirection.ascending.title,
                descending: CatalogSortDirection.descending.title,
                unavailable: String(localized: "Sorting is unavailable")
            ),
            visualStyle: .cadence
        )
    }

    private var fieldBinding: Binding<Field> {
        Binding(
            get: { selection.field },
            set: { field in
                var next = selection
                next.select(field: field)
                selection = next
            }
        )
    }

    private var orderBinding: Binding<SortMenuOrder> {
        Binding(
            get: {
                selection.direction == .ascending ? .ascending : .descending
            },
            set: { order in
                var next = selection
                next.select(
                    direction: order == .ascending ? .ascending : .descending
                )
                selection = next
            }
        )
    }
}
