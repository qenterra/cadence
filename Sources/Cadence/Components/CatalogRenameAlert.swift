import QenTerraComponents
import SwiftUI

extension View {
    func catalogRenameAlert(
        _ title: String,
        prompt: String,
        isPresented: Binding<Bool>,
        draft: Binding<String>,
        onRename: @escaping (String) -> Void
    ) -> some View {
        let isValid = !draft.wrappedValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        return renameAlert(
            configuration: RenameAlertConfiguration(
                title: title,
                fieldLabel: prompt,
                initialText: draft.wrappedValue,
                validation: isValid ? .valid : .invalid(message: "Name is required."),
                confirmLabel: "Rename",
                cancelLabel: "Cancel"
            ),
            isPresented: isPresented,
            text: draft,
            onConfirm: onRename
        )
    }
}
