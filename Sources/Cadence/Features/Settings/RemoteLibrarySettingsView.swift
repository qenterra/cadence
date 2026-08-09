import AppKit
import SwiftUI

struct RemoteLibrarySettingsView: View {
    @Bindable var controller: RemoteLibraryController
    @State private var isConnectionSheetPresented = false

    var body: some View {
        SettingsCard(
            title: "Remote Media",
            symbol: "network"
        ) {
            LabeledContent("Status") {
                Label(statusTitle, systemImage: statusSymbol)
                    .foregroundStyle(statusColor)
            }

            if let detail = statusDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Picker("Local Cache", selection: cacheBudgetBinding) {
                ForEach(Self.cacheBudgets, id: \.bytes) { option in
                    Text(option.title).tag(option.bytes)
                }
            }
            .disabled(isConnecting)

            HStack {
                Button("Connect…", systemImage: "network.badge.shield.half.filled") {
                    isConnectionSheetPresented = true
                }
                .disabled(isConnecting)

                if controller.configuredProviderName != nil {
                    Button("Disconnect", role: .destructive) {
                        Task { await controller.disconnect() }
                    }
                    .disabled(isConnecting)
                }
            }

            Text(
                "Cadence keeps the catalog local. Remote audio is downloaded into a "
                    + "bounded cache, verified with SHA-256, and only then passed to playback."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $isConnectionSheetPresented) {
            RemoteLibraryConnectionSheet(
                controller: controller,
                isPresented: $isConnectionSheetPresented
            )
        }
    }

    private var cacheBudgetBinding: Binding<Int64> {
        Binding(
            get: { controller.cacheBudgetBytes },
            set: { value in
                Task { await controller.setCacheBudget(value) }
            }
        )
    }

    private var isConnecting: Bool {
        controller.status == .connecting
    }

    private var statusTitle: String {
        switch controller.status {
        case .disconnected: "Not Connected"
        case .connecting: "Connecting…"
        case let .ready(provider, _): provider
        case .unavailable: "Unavailable"
        }
    }

    private var statusDetail: String? {
        switch controller.status {
        case let .ready(_, trackCount):
            "\(trackCount.formatted()) remote media objects are available."
        case let .unavailable(message):
            message
        case .disconnected, .connecting:
            nil
        }
    }

    private var statusSymbol: String {
        switch controller.status {
        case .disconnected: "network.slash"
        case .connecting: "arrow.trianglehead.2.clockwise.rotate.90"
        case .ready: "checkmark.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .ready: .green
        case .unavailable: .orange
        case .disconnected, .connecting: .secondary
        }
    }

    private static let cacheBudgets: [(title: String, bytes: Int64)] = [
        ("2 GB", 2 * 1024 * 1024 * 1024),
        ("5 GB", 5 * 1024 * 1024 * 1024),
        ("10 GB", 10 * 1024 * 1024 * 1024),
        ("25 GB", 25 * 1024 * 1024 * 1024),
        ("50 GB", 50 * 1024 * 1024 * 1024),
    ]
}

private struct RemoteLibraryConnectionSheet: View {
    enum Provider: String, CaseIterable, Identifiable {
        case webDAV = "WebDAV"
        case googleDrive = "Google Drive"

        var id: Self {
            self
        }
    }

    @Bindable var controller: RemoteLibraryController
    @Binding var isPresented: Bool
    @State private var provider = Provider.webDAV
    @State private var webDAVURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var clientID = ""
    @State private var folderID = ""
    @State private var manifestFileID = ""
    @State private var redirectURL = "com.qenterra.cadence:/oauth2redirect"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Connect Remote Media")
                .font(.title2.bold())

            Picker("Provider", selection: $provider) {
                ForEach(Provider.allCases) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            Group {
                if provider == .webDAV {
                    TextField("Server URL", text: $webDAVURL)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                } else {
                    TextField("OAuth Client ID", text: $clientID)
                    TextField("Drive Folder ID", text: $folderID)
                    TextField("Manifest File ID", text: $manifestFileID)
                    TextField("Redirect URL", text: $redirectURL)
                    Text(
                        "Google Drive requires the Cadence OAuth client and a manifest "
                            + "created by Cadence with that client. Tokens stay in Keychain."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                Button("Connect") {
                    connect()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConnect)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var canConnect: Bool {
        switch provider {
        case .webDAV:
            URL(string: webDAVURL) != nil
                && !username.isEmpty
                && !password.isEmpty
        case .googleDrive:
            !clientID.isEmpty
                && !folderID.isEmpty
                && !manifestFileID.isEmpty
                && URL(string: redirectURL) != nil
                && NSApp.keyWindow != nil
        }
    }

    private func connect() {
        isPresented = false
        Task {
            switch provider {
            case .webDAV:
                guard let url = URL(string: webDAVURL) else {
                    return
                }
                await controller.connectWebDAV(
                    rootURL: url,
                    username: username,
                    password: password
                )
            case .googleDrive:
                guard let redirectURL = URL(string: redirectURL),
                      let window = NSApp.keyWindow
                else {
                    return
                }
                await controller.connectGoogleDrive(
                    drive: GoogleDriveConfiguration(
                        folderID: folderID,
                        manifestFileID: manifestFileID
                    ),
                    clientID: clientID,
                    redirectURL: redirectURL,
                    presentingWindow: window
                )
            }
        }
    }
}
