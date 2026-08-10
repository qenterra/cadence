import SwiftUI

extension View {
    func catalogRenameAlert(
        _ title: LocalizedStringKey,
        prompt: LocalizedStringKey,
        isPresented: Binding<Bool>,
        draft: Binding<String>,
        onRename: @escaping (String) -> Void
    ) -> some View {
        alert(title, isPresented: isPresented) {
            TextField(prompt, text: draft)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                onRename(draft.wrappedValue)
            }
            .disabled(
                draft.wrappedValue.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            )
        }
    }
}
