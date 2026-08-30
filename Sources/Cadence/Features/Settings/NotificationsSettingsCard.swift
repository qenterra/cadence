import SwiftUI

struct NotificationsSettingsCard: View {
    let notificationController: CadenceNotificationController
    @AppStorage(CadenceNotificationPreferences.trackChangesKey)
    private var notifiesWhenTrackChanges = false
    @AppStorage(CadenceNotificationPreferences.updateAvailabilityKey)
    private var notifiesWhenUpdateIsAvailable = false
    @State private var authorizationDenied = false

    var body: some View {
        SettingsCard(
            title: String(localized: "Notifications"),
            symbol: "bell.badge"
        ) {
            SettingsToggleRow(
                "When Track Changes",
                isOn: trackNotificationsBinding
            )

            SettingsToggleRow(
                "When Updates Are Available",
                isOn: updateNotificationsBinding
            )

            notificationHelp
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var notificationHelp: some View {
        if authorizationDenied {
            Text("Notifications are disabled for Cadence in System Settings.")
        } else {
            Text(
                """
                Cadence asks for permission only when you enable an alert. \
                Delivery follows macOS notification and Focus settings.
                """
            )
        }
    }

    private var trackNotificationsBinding: Binding<Bool> {
        Binding(
            get: { notifiesWhenTrackChanges },
            set: { isEnabled in
                guard isEnabled else {
                    notifiesWhenTrackChanges = false
                    return
                }
                authorizeNotifications {
                    notifiesWhenTrackChanges = true
                }
            }
        )
    }

    private var updateNotificationsBinding: Binding<Bool> {
        Binding(
            get: { notifiesWhenUpdateIsAvailable },
            set: { isEnabled in
                guard isEnabled else {
                    notifiesWhenUpdateIsAvailable = false
                    return
                }
                authorizeNotifications {
                    notifiesWhenUpdateIsAvailable = true
                }
            }
        )
    }

    private func authorizeNotifications(
        enable: @escaping @MainActor () -> Void
    ) {
        Task { @MainActor in
            if await notificationController.requestAuthorizationIfNeeded() {
                enable()
                authorizationDenied = false
            } else {
                authorizationDenied = true
            }
        }
    }
}
