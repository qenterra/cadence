import SwiftUI

struct NotificationsSettingsCard: View {
    let notificationController: CadenceNotificationController
    @AppStorage(CadenceNotificationPreferences.trackChangesKey)
    private var notifiesWhenTrackChanges = false
    @AppStorage(CadenceNotificationPreferences.updateAvailabilityKey)
    private var notifiesWhenUpdateIsAvailable = false
    @AppStorage(CadenceNotificationPreferences.foregroundBannersKey)
    private var showsForegroundBanners = true
    @State private var authorizationDenied = false

    var body: some View {
        SettingsCard(
            title: String(localized: "Notifications"),
            symbol: "bell.badge"
        ) {
            SettingsToggleRow(
                "New track",
                isOn: trackNotificationsBinding
            )

            SettingsToggleRow(
                "New version available",
                isOn: updateNotificationsBinding
            )

            SettingsToggleRow(
                "Show banners when Cadence is open",
                isOn: $showsForegroundBanners
            )

            notificationHelp
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var notificationHelp: some View {
        if authorizationDenied {
            Text("Allow Cadence notifications in System Settings to use these options.")
        } else {
            Text("macOS controls notification delivery and Focus filtering.")
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
