import SwiftUI

struct BackupActionsSheet: View {
    @Environment(ThemeStore.self) private var theme

    let snapshot: LibrarySnapshotDTO
    let exportName: String
    let isRestoring: Bool
    let onClose: () -> Void
    let onRename: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HeartableDrawer { content }
            .accessibilityAction(.escape, onClose)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup actions")
                        .font(Typography.heading(23))
                        .foregroundStyle(theme.palette.text)
                    Text(snapshot.name?.isEmpty == false ? snapshot.name! : "Heartable backup")
                        .font(Typography.body(13))
                        .foregroundStyle(theme.palette.textSecondary)
                }
                Spacer(minLength: 8)
            }

            VStack(spacing: 9) {
                Button(action: onRename) {
                    actionRow(icon: "pencil", title: "Rename", destructive: false)
                }
                .buttonStyle(.plain)

                ShareLink(
                    item: CSVDocument(snapshot: snapshot),
                    preview: SharePreview("\(exportName).csv")
                ) {
                    actionRow(
                        icon: "square.and.arrow.up",
                        title: "Export CSV",
                        destructive: false
                    )
                }
                .buttonStyle(.plain)

                Button(action: onRestore) {
                    actionRow(
                        icon: "arrow.uturn.backward",
                        title: isRestoring ? "Restoring…" : "Restore to Spotify",
                        destructive: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)

                Button(role: .destructive, action: onDelete) {
                    actionRow(
                        icon: "trash.fill",
                        title: "Delete backup",
                        destructive: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(theme.palette.bg.ignoresSafeArea())
        .accessibilityAction(.escape, onClose)
    }

    private func actionRow(
        icon: String,
        title: String,
        destructive: Bool
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    destructive
                        ? theme.palette.danger.opacity(0.12)
                        : theme.palette.roseDim
                )
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            destructive
                                ? theme.palette.danger
                                : theme.palette.rose
                        )
                }
            Text(title)
                .font(Typography.semibold(14))
                .foregroundStyle(
                    destructive ? theme.palette.danger : theme.palette.text
                )
            Spacer()
        }
        .padding(.horizontal, 13)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(theme.palette.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(theme.palette.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}
