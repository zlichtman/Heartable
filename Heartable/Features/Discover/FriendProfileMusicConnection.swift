import Foundation
import SwiftUI

/// A compatibility score is only presented after both people have enough
/// distinct, recent Heartable plays to keep a tiny sample from looking precise.
enum FriendCompatibilityAvailability: Sendable, Equatable {
    static let minimumDistinctTracksPerPerson = 5

    case available(FriendCompatibilitySummary)
    case insufficient

    static func evaluate(
        entries: [SongLeaderboardEntryDTO],
        viewerID: UUID,
        friendID: UUID
    ) -> FriendCompatibilityAvailability {
        guard let summary = FriendCompatibilitySummary.build(
            entries: entries,
            viewerID: viewerID,
            friendID: friendID
        ),
        summary.viewerTrackCount >= minimumDistinctTracksPerPerson,
        summary.friendTrackCount >= minimumDistinctTracksPerPerson else {
            return .insufficient
        }
        return .available(summary)
    }
}

struct FriendCompatibilityCard: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let availability: FriendCompatibilityAvailability
    let friendName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.palette.rose)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Music compatibility")
                        .font(Typography.heading(20))
                        .foregroundStyle(theme.palette.text)
                    Text("From the last 30 days in Heartable")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textMuted)
                }
            }

            switch availability {
            case .available(let summary):
                availableContent(summary)
            case .insufficient:
                insufficientContent
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(
                cornerRadius: Theme.Radius.lg,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [
                        theme.palette.card,
                        theme.palette.grad1.opacity(0.16),
                        theme.palette.rose.opacity(0.09),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: Theme.Radius.lg,
                style: .continuous
            )
            .stroke(theme.palette.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func availableContent(_ summary: FriendCompatibilitySummary) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                score(summary)
                overlap(summary)
            }
        } else {
            HStack(alignment: .center, spacing: 16) {
                score(summary)
                Divider()
                    .overlay(theme.palette.border)
                overlap(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        if !summary.sharedTracks.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(summary.sharedTracks.enumerated()), id: \.element.id) {
                    index,
                    track in
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.palette.rose)
                            .frame(width: 26, height: 26)
                            .background(theme.palette.roseDim, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.trackName)
                                .font(Typography.semibold(13))
                                .foregroundStyle(theme.palette.text)
                                .lineLimit(2)
                            if let artist = track.artist, !artist.isEmpty {
                                Text(artist)
                                    .font(Typography.body(11))
                                    .foregroundStyle(theme.palette.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 9)
                    .accessibilityElement(children: .combine)

                    if index < summary.sharedTracks.count - 1 {
                        Divider().overlay(theme.palette.border)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(
                theme.palette.card.opacity(0.72),
                in: RoundedRectangle(cornerRadius: Theme.Radius.md)
            )
        }
    }

    private func score(_ summary: FriendCompatibilitySummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(summary.score)%")
                .font(Typography.heading(34))
                .foregroundStyle(theme.palette.rose)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(scoreLabel(summary.score))
                .font(Typography.medium(12))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.score) percent music compatibility")
    }

    private func overlap(_ summary: FriendCompatibilitySummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                "\(summary.sharedTrackCount) shared "
                    + (summary.sharedTrackCount == 1 ? "track" : "tracks")
            )
            .font(Typography.semibold(14))
            .foregroundStyle(theme.palette.text)
            Text(
                "\(summary.viewerTrackCount) in your rotation · "
                    + "\(summary.friendTrackCount) in \(friendName)’s"
            )
            .font(Typography.body(11))
            .foregroundStyle(theme.palette.textMuted)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
        }
        .accessibilityElement(children: .combine)
    }

    private var insufficientContent: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.palette.textSecondary)
                .frame(width: 40, height: 40)
                .background(theme.palette.surface, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Still learning your overlap")
                    .font(Typography.semibold(15))
                    .foregroundStyle(theme.palette.text)
                Text(
                    "A score appears after you and \(friendName) each have "
                        + "\(Self.minimumTrackCount) distinct tracks recorded "
                        + "in Heartable during this window."
                )
                .font(Typography.body(12))
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private static var minimumTrackCount: Int {
        FriendCompatibilityAvailability.minimumDistinctTracksPerPerson
    }

    private func scoreLabel(_ score: Int) -> String {
        switch score {
        case 80...: "Same wavelength"
        case 55...: "Plenty in common"
        case 30...: "A shared spark"
        default: "Different rotations"
        }
    }
}

struct FriendMixtapeEntryCard: View {
    @Environment(ThemeStore.self) private var theme

    let friendName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: "cassette.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.palette.rose)
                    .frame(width: 48, height: 48)
                    .background(theme.palette.roseDim, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mixtape")
                        .font(Typography.semibold(16))
                        .foregroundStyle(theme.palette.text)
                    Text("Songs, notes, photos — for \(friendName)")
                        .font(Typography.body(12))
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.palette.rose)
                    .frame(width: 44, height: 44)
                    .background(theme.palette.roseDim, in: Circle())
                    .accessibilityHidden(true)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.palette.card,
                in: RoundedRectangle(
                    cornerRadius: Theme.Radius.lg,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: Theme.Radius.lg,
                    style: .continuous
                )
                .stroke(theme.palette.border, lineWidth: 1)
            }
            .contentShape(
                RoundedRectangle(
                    cornerRadius: Theme.Radius.lg,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Make a mixtape for \(friendName)")
        .accessibilityHint("Add songs, notes, and photos, then send it when ready")
    }
}

enum FriendMixtapeCreationError: LocalizedError, Equatable {
    case emptyTitle
    case creationFailed

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "Give your mixtape a name."
        case .creationFailed:
            "Heartable couldn’t create that mixtape."
        }
    }
}

@MainActor
struct FriendMixtapeCreator {
    var create: @MainActor (String, UUID) async throws -> UUID?

    static let live = FriendMixtapeCreator(
        create: { title, friendID in
            try await BackendAPI.shared.createMixtape(title: title, recipientID: friendID)
        }
    )

    func createDraft(
        title rawTitle: String,
        friendID: UUID
    ) async throws -> UUID {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            throw FriendMixtapeCreationError.emptyTitle
        }
        guard let mixtapeID = try await create(title, friendID) else {
            throw FriendMixtapeCreationError.creationFailed
        }
        return mixtapeID
    }
}

struct SharedMixtapeComposerSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(BannerCenter.self) private var banners
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    let friendID: UUID
    let friendName: String
    let onCreated: (UUID) -> Void

    @State private var title = ""
    @State private var creating = false
    @State private var errorMessage: String?

    var body: some View {
        HeartableDrawer {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "cassette.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(theme.palette.rose)
                            .frame(width: 58, height: 58)
                            .background(theme.palette.roseDim, in: Circle())
                            .accessibilityHidden(true)
                        Text("A mixtape for \(friendName)")
                            .font(Typography.heading(26))
                            .foregroundStyle(theme.palette.text)
                        Text(
                            "Add songs, photos, and a personal note. Send it when it’s ready."
                        )
                        .font(Typography.body(13))
                        .foregroundStyle(theme.palette.textSecondary)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Title")
                            .font(Typography.semibold(12))
                            .foregroundStyle(theme.palette.textSecondary)
                        TextField("Late-night favorites", text: $title)
                            .font(Typography.medium(16))
                            .foregroundStyle(theme.palette.text)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .focused($titleFocused)
                            .onSubmit { createIfPossible() }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(
                                theme.palette.surface,
                                in: RoundedRectangle(
                                    cornerRadius: Theme.Radius.md,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                RoundedRectangle(
                                    cornerRadius: Theme.Radius.md,
                                    style: .continuous
                                )
                                .stroke(
                                    titleFocused
                                        ? theme.palette.rose
                                        : theme.palette.border,
                                    lineWidth: titleFocused ? 1.5 : 1
                                )
                            }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(Typography.body(12))
                            .foregroundStyle(theme.palette.danger)
                            .accessibilityElement(children: .combine)
                    }

                    Button {
                        createIfPossible()
                    } label: {
                        HStack(spacing: 8) {
                            if creating {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "heart.fill")
                                    .accessibilityHidden(true)
                            }
                            Text(creating ? "Creating…" : "Start mixtape")
                                .font(Typography.semibold(16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(theme.palette.rose, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(creating || normalizedTitle.isEmpty)
                    .opacity(normalizedTitle.isEmpty ? 0.55 : 1)
                }
                .padding(20)
            .task { titleFocused = true }
        }
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createIfPossible() {
        guard !creating, !normalizedTitle.isEmpty else { return }
        creating = true
        errorMessage = nil
        Task {
            do {
                let mixtapeID = try await FriendMixtapeCreator.live.createDraft(
                    title: normalizedTitle,
                    friendID: friendID
                )
                dismiss()
                onCreated(mixtapeID)
            } catch {
                errorMessage = error.localizedDescription
                creating = false
            }
        }
    }
}
