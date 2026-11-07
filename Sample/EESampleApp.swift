import SwiftUI
import CoreBluetooth
import CoreLocation
import EEGatewaySDK

/// Minimal host app (S7) — the iOS counterpart of ee-sdk-android's :sample.
/// ONE screen: token paste / Start / Stop / live status. Doubles as the C10
/// reference code for the three things a real fleet app must own:
///
///  1. **The permission UX.** The SDK never prompts (contract), so this app
///     does: instantiating CBCentralManager fires the Bluetooth dialog, and
///     CLLocationManager drives the location one. A real fleet app already
///     holds both grants, so its integration is just configure()+start().
///  2. **Info.plist declarations** — see Sample/README.md for the exact
///     keys (usage strings + background modes).
///  3. **Lifecycle** — start() from the app lifecycle; the SDK survives
///     backgrounding through the host's `bluetooth-central` background mode.
@main
struct EESampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var token = ""
    @State private var status = EEGateway.status()
    @State private var selfMint = true

    /// Held so the Bluetooth permission dialog's answer sticks around; the
    /// SDK creates its own central only after authorization is determined.
    @State private var permissionPrimer: CBCentralManager?
    private let locationManager = CLLocationManager()

    var body: some View {
        NavigationView {
            Form {
                Section("Permissions (the host app's job, not the SDK's)") {
                    Button("1. Request Bluetooth") {
                        // Creating a central IS the prompt.
                        permissionPrimer = CBCentralManager()
                    }
                    Button("2. Request Location (Always)") {
                        locationManager.requestWhenInUseAuthorization()
                        locationManager.requestAlwaysAuthorization()
                    }
                }

                Section("Identity") {
                    Toggle("Self-mint (demo mode)", isOn: $selfMint)
                    if !selfMint {
                        TextField("ee_live_… token from your backend", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section("Gateway") {
                    Button("Start") {
                        EEGateway.configure(
                            selfMint ? .selfMint() : .gatewayToken(token: token)
                        )
                        EEGateway.start()
                    }
                    Button("Stop") { EEGateway.stop() }
                }

                Section("Live status") {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 12, height: 12)
                        Text(stateLabel)
                            .bold()
                        Spacer()
                        if status.state == .running {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundColor(.green)
                        }
                    }
                    row("Pings heard", "\(status.pingsHeard)")
                    row("Forwarded", "\(status.packetsForwarded)")
                    row("Queue depth", "\(status.queueDepth)")
                    row("Gateway", status.gatewayPublicId ?? "—")
                    row("Last heartbeat", heartbeatAge)
                }
            }
            .navigationTitle("EE Gateway SDK")
        }
        .onAppear {
            // Main-queue delivery and ≤~1/s coalescing are the SDK contract,
            // so assigning into @State directly is safe.
            EEGateway.setListener { status = $0 }
            status = EEGateway.status()
        }
    }

    private var stateColor: Color {
        switch status.state {
        case .running: return .green
        case .awaitingPermissions, .pausedRemote: return .orange
        case .ready: return .blue
        case .unconfigured, .stopped: return .gray
        }
    }

    private var stateLabel: String {
        switch status.state {
        case .unconfigured: return "Not configured"
        case .ready: return "Ready — tap Start"
        case .awaitingPermissions: return "Waiting for permissions…"
        case .running: return "RUNNING — relaying"
        case .pausedRemote: return "Paused by fleet kill switch"
        case .stopped: return "Stopped"
        }
    }

    private var heartbeatAge: String {
        guard let at = status.lastHeartbeatAt else { return "—" }
        let seconds = Int64(Date().timeIntervalSince1970 * 1000 - Double(at)) / 1000
        return "\(seconds)s ago"
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary).monospacedDigit()
        }
    }
}
