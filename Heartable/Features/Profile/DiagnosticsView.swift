import SwiftUI

/// What MetricKit reported about Heartable on this device. Crashes and hangs
/// arrive on the launch after they happen; memory-limit and watchdog exits
/// arrive as daily counts. Sharing is the tester's choice, entry by entry.
struct DiagnosticsView: View {
    @Environment(ThemeStore.self) private var theme
    @State private var entries: [DiagnosticEntry] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Crash, hang, and memory-limit reports iOS gave Heartable about itself. They stay on this iPhone unless you share one.")
                    .font(Typography.body(13))
                    .foregroundStyle(theme.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if loaded && entries.isEmpty {
                    Text("No reports yet. iOS delivers them on the launch after a crash, and abnormal-exit counts about once a day.")
                        .font(Typography.body(14))
                        .foregroundStyle(theme.palette.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }

                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(label(for: entry.kind))
                                .font(Typography.semibold(15))
                                .foregroundStyle(entry.kind == "crash" ? theme.palette.danger : theme.palette.text)
                            Spacer()
                            Text("build \(entry.build)")
                                .font(Typography.body(12))
                                .foregroundStyle(theme.palette.textMuted)
                        }
                        Text(entry.receivedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.textMuted)
                        Text(entry.summary)
                            .font(Typography.body(13))
                            .foregroundStyle(theme.palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ShareLink(item: entry.shareText, subject: Text("Heartable \(entry.kind) report")) {
                            Label("Share report", systemImage: "square.and.arrow.up")
                                .font(Typography.semibold(13))
                                .foregroundStyle(theme.palette.rose)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.palette.card)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(theme.palette.border, lineWidth: 1)
                    }
                }

                if !entries.isEmpty {
                    ShareLink(item: entries.map(\.shareText).joined(separator: "\n\n----\n\n"),
                              subject: Text("Heartable diagnostics")) {
                        Label("Share all reports", systemImage: "square.and.arrow.up.on.square")
                            .font(Typography.semibold(14))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(theme.palette.rose, in: RoundedRectangle(cornerRadius: Theme.Radius.full))
                    }
                    .buttonStyle(.plain)
                    Button {
                        Task {
                            await DiagnosticsStore.shared.clear()
                            entries = []
                        }
                    } label: {
                        Text("Clear reports")
                            .font(Typography.semibold(13))
                            .foregroundStyle(theme.palette.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(theme.palette.bg.ignoresSafeArea())
        .navigationTitle("Diagnostics")
        .task {
            entries = await DiagnosticsStore.shared.entries()
            loaded = true
        }
    }

    private func label(for kind: String) -> String {
        switch kind {
        case "crash": "Crash"
        case "hang": "Hang"
        case "cpu": "CPU exception"
        case "diskWrite": "Disk write exception"
        case "exits": "Abnormal exits"
        default: kind.capitalized
        }
    }
}
