import SwiftUI
import PhotosUI

struct MixtapeSongNoteSheet: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(BannerCenter.self) private var banners
    @Environment(\.dismiss) private var dismiss
    let mixtapeID: UUID
    let track: MixtapeTrackDTO
    let onSaved: () async -> Void
    @State private var note: String
    @State private var photo: PhotosPickerItem?
    @State private var previewURL: String?
    @State private var replacement: String?
    @State private var removedPhoto = false
    @State private var saving = false
    @State private var uploading = false

    init(mixtapeID: UUID, track: MixtapeTrackDTO, onSaved: @escaping () async -> Void) {
        self.mixtapeID = mixtapeID
        self.track = track
        self.onSaved = onSaved
        _note = State(initialValue: track.note ?? "")
        _previewURL = State(initialValue: track.noteImageUrl)
    }

    var body: some View {
        let photoButtonTitle = uploading ? "Uploading…" : "Add photo"
        HeartableDrawer {
            VStack(alignment: .leading, spacing: 18) {
                Text(track.trackName ?? "Song note").font(Typography.heading(24)).foregroundStyle(theme.palette.text)
                TextField("What makes this song special?", text: $note, axis: .vertical)
                    .lineLimit(3...8).font(Typography.body(16)).foregroundStyle(theme.palette.text)
                    .padding(14).background(theme.palette.surface, in: RoundedRectangle(cornerRadius: 14))
                if let previewURL, !previewURL.isEmpty {
                    ArtworkThumb(urlString: previewURL, size: 180, corner: 14)
                }
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(photoButtonTitle, systemImage: "photo.badge.plus")
                            .frame(minHeight: 44)
                    }.disabled(uploading || saving)
                    Spacer()
                    if previewURL?.isEmpty == false {
                        Button("Remove photo") {
                            previewURL = nil
                            replacement = nil
                            removedPhoto = true
                        }.disabled(uploading || saving)
                    }
                }.font(Typography.medium(13)).foregroundStyle(theme.palette.rose)
                Button { Task { await save() } } label: {
                    Text(saving ? "Saving…" : "Save")
                        .font(Typography.semibold(16)).foregroundStyle(theme.palette.bg)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(theme.palette.rose, in: Capsule())
                }.buttonStyle(.plain).disabled(saving || uploading)
            }.padding(20)
        }
        .interactiveDismissDisabled(saving || uploading)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                uploading = true
                defer { uploading = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let jpeg = ImageDownscale.jpeg(from: data) else { throw ProviderError("Invalid photo") }
                    let reference = try await BackendAPI.shared.uploadMixtapeImage(mixtapeID: mixtapeID, jpeg)
                    replacement = reference
                    removedPhoto = false
                    previewURL = await BackendAPI.shared.mixtapeMediaDisplayURL(reference)
                } catch { banners.error("Couldn’t upload that photo. Try again.") }
            }
        }
    }

    private func save() async {
        guard !saving, !uploading else { return }
        saving = true
        defer { saving = false }
        do {
            // An empty string explicitly removes the optional image; nil omits
            // the update and preserves an existing private storage reference.
            let imageChange: String?? = removedPhoto ? .some("") : replacement.map { .some($0) }
            try await BackendAPI.shared.updateMixtapeTrack(id: track.id, note: note, noteImageUrl: imageChange)
            await onSaved()
            dismiss()
        } catch { banners.error("Couldn’t save your note. Try again.") }
    }
}
