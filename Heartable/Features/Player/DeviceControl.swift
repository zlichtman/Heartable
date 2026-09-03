import SwiftUI
import AVKit
import UIKit

/// Unified "where is this playing" control, shared by the mini-player bar and the
/// full player. The destination ecosystem differs per source, so the button adapts:
///
/// - **Spotify** plays on a Spotify Connect device (phone app, desktop, speaker),
///   so the button opens a Connect-device picker that transfers playback via the
///   Web API — no leaving the app.
/// - **Apple Music / Audius / Deezer** play through the app's shared audio session,
///   so the button is the native **AirPlay** route picker, which relocates the
///   system audio output (AirPlay, Bluetooth, etc.) in a single tap.
///
/// Same affordance everywhere; each source routes to the device ecosystem it can
/// actually reach (Apple Music can't target Spotify Connect, and vice versa).
struct DeviceButton: View {
    @Environment(ThemeStore.self) private var theme

    let source: ProviderID
    var size: CGFloat = 20

    @State private var showSpotifyDevices = false

    var body: some View {
        let target = max(44, size + 14)
        Group {
            if source == .spotify {
                Button { showSpotifyDevices = true } label: {
                    Image(systemName: "hifispeaker.2.fill")
                        .font(.system(size: size))
                        .foregroundStyle(theme.palette.text)
                        .frame(width: target, height: target)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose Spotify device")
                .sheet(isPresented: $showSpotifyDevices) {
                    SpotifyDevicePickerSheet()
                        .environment(theme)
                }
            } else {
                AirPlayRouteButton(tint: UIColor(theme.palette.text))
                    .frame(width: target, height: target)
                    .accessibilityLabel("Choose audio output")
            }
        }
    }
}

/// SwiftUI wrapper over `AVRoutePickerView` — the system AirPlay/output picker.
/// Controls the shared `AVAudioSession` route, which is what `ApplicationMusicPlayer`
/// (Apple Music) and the local `AVPlayer` (Audius/Deezer) both play through.
private struct AirPlayRouteButton: UIViewRepresentable {
    let tint: UIColor

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = tint
        view.prioritizesVideoDevices = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = tint
    }
}

/// Lists Spotify Connect devices and transfers playback to the one you tap. The
/// active device is checkmarked; tapping another moves playback to it via the Web
/// API and re-reads the list to reflect the change.
struct SpotifyDevicePickerSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(PlayerStore.self) private var player
    @Environment(BannerCenter.self) private var banners
    @Environment(\.dismiss) private var dismiss

    @State private var devices: [SpotifyDevice] = []
    @State private var loading = true
    @State private var busyID: String?
    @State private var loadMessage =
        "No Spotify Connect devices are currently available."

    var body: some View {
        HeartableDrawer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Playback device")
                        .font(Typography.heading(23))
                        .foregroundStyle(theme.palette.text)
                    Spacer(minLength: 8)
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(theme.palette.rose)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(loading || busyID != nil)
                    .accessibilityLabel("Refresh devices")
                }
                VStack(alignment: .leading, spacing: 8) {
                    if loading {
                        HStack { Spacer(); ProgressView().tint(theme.palette.rose); Spacer() }
                            .padding(.vertical, 12)
                    } else if devices.isEmpty {
                        VStack(spacing: 8) {
                            Text("No Spotify devices found")
                                .font(Typography.semibold(15))
                                .foregroundStyle(theme.palette.text)
                            Text(
                                loadMessage
                            )
                                .font(Typography.body(13))
                                .foregroundStyle(theme.palette.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else {
                        ForEach(devices, id: \.id) { device in
                            deviceRow(device)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .task { await load() }
    }

    private func deviceRow(_ device: SpotifyDevice) -> some View {
        Button {
            Task { await select(device) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: device))
                    .font(.system(size: 18))
                    .foregroundStyle(device.isActive ? theme.palette.rose : theme.palette.text)
                    .frame(width: 30)
                Text(device.name ?? "Spotify device")
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                Spacer(minLength: 8)
                if busyID == device.id {
                    ProgressView().tint(theme.palette.rose)
                } else if device.isActive {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.palette.rose)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(busyID != nil)
        .accessibilityValue(device.isActive ? "Current device" : "")
    }

    private func icon(for device: SpotifyDevice) -> String {
        let n = "\(device.type ?? "") \(device.name ?? "")".lowercased()
        if n.contains("iphone") || n.contains("phone") { return "iphone" }
        if n.contains("ipad") { return "ipad" }
        if n.contains("mac") || n.contains("computer") || n.contains("pc") { return "laptopcomputer" }
        if n.contains("tv") { return "appletv" }
        if n.contains("watch") { return "applewatch" }
        return "hifispeaker"
    }

    private func load() async {
        loading = true
        if let token = await SpotifyAuth.getValidAccessToken() {
            switch await SpotifyAPI.discoverDevices(token: token) {
            case .available(let available):
                devices = available
            case .none:
                devices = []
                loadMessage =
                    "Spotify has not exposed a Connect device yet. "
                    + "Refresh when one becomes available."
            case .unavailable:
                devices = []
                loadMessage =
                    "Spotify found devices, but they are restricted or cannot "
                    + "accept playback."
            case .unauthorized:
                devices = []
                loadMessage = "Your Spotify session expired. Reconnect Spotify in Music Services."
            case .forbidden:
                devices = []
                loadMessage =
                    "Spotify did not permit Connect control for this account or app."
            case .rateLimited(let retry):
                devices = []
                loadMessage =
                    "Spotify asked Heartable to wait \(max(1, Int(retry.rounded()))) seconds "
                    + "before checking again."
            case .failed:
                devices = []
                loadMessage =
                    "Heartable couldn't check Spotify devices. "
                    + "Check your connection and refresh."
            }
        } else {
            devices = []
            loadMessage = "Reconnect Spotify in Music Services to choose a device."
        }
        loading = false
    }

    private func select(_ device: SpotifyDevice) async {
        guard let id = device.id,
              let token = await SpotifyAuth.getValidAccessToken() else { return }
        busyID = id
        let transferred = await SpotifyAPI.transferPlayback(
            token: token,
            deviceId: id,
            play: false
        )
        guard transferred else {
            banners.error("Spotify couldn't switch to that device.")
            busyID = nil
            return
        }
        let startedPending = await player.startPendingSpotify(on: id)
        if startedPending {
            banners.success("Playback moved to \(device.name ?? "Spotify device")")
        } else {
            banners.info("Connected to \(device.name ?? "Spotify device")")
        }
        busyID = nil
        dismiss()
    }
}
