#if DEBUG
import SwiftUI

/// Debug-only screens for capturing marketing screenshots without an account.
/// Launch the simulator build with `-HeartableScreenshot <name>`; only the
/// mixtape editor and vinyl shelf are available. Nothing here ships in Release.
enum ScreenshotFixtures {
    static var requested: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-HeartableScreenshot"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static let recipientName = "Ava"

    static func mixtape() -> MixtapeDetailDTO {
        let mixtapeID = UUID(uuidString: "6E7A1C2B-4D5F-4A6B-8C9D-0E1F2A3B4C5D")!
        let owner = UUID()
        var tape = MixtapeDTO(
            id: mixtapeID, owner: owner,
            title: "Drive Home",
            description: "for the long way back, in the order we argued about them",
            coverUrl: "heartable-fixture://mixtape-scenery",
            createdAt: "2026-02-10T18:04:00Z",
            recipientId: UUID(),
            sentAt: "2026-02-14T09:12:00Z"
        )
        tape.mine = true
        let rows: [[String: Any]] = [
            track("spotify:track:1611367446", "Motion Sickness", "Phoebe Bridgers",
                  "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/20/4c/6e/204c6ef3-8e95-4cee-2256-202ca62aebed/60220.jpg/600x600bb.jpg", 229760,
                  note: "three times in a row on I-94, so it goes first"),
            track("apple:song:1685281655", "Chamber of Reflection", "Mac DeMarco",
                  "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/e0/04/eb/e004eb2b-754f-4a76-9ecc-87d4eea2a327/cover.jpg/600x600bb.jpg", 231724),
            track("spotify:track:1760834263", "Sofia", "Clairo",
                  "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/f2/47/06/f24706bc-a90c-f730-bd8a-586ddde8af3e/829299184631.jpg/600x600bb.jpg", 188387,
                  note: "windows down, even in February",
                  photo: "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/d2/48/f4/d248f4ae-a7e4-a48e-1588-6617de3e8d76/mzi.izeorbmm.jpg/600x600bb.jpg"),
            track("apple:song:1763689163", "Apocalypse", "Cigarettes After Sex",
                  "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/b3/5e/0f/b35e0fbe-2370-fc48-0f0c-977525e93bf2/720841214601_Cover.jpg/600x600bb.jpg", 290147),
            track("spotify:track:1763685041", "Northern Attitude", "Noah Kahan",
                  "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/ad/6b/4c/ad6b4cab-ef20-9dbf-e24e-f4b81118c86a/23UM1IM22838.rgb.jpg/600x600bb.jpg", 267256),
            track("apple:song:1440815010", "Dreams", "Fleetwood Mac",
                  "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/d2/48/f4/d248f4ae-a7e4-a48e-1588-6617de3e8d76/mzi.izeorbmm.jpg/600x600bb.jpg", 254453,
                  note: "you know why"),
        ]
        let data = try! JSONSerialization.data(withJSONObject: rows.enumerated().map { offset, row in
            var row = row
            row["position"] = offset
            row["mixtape_id"] = mixtapeID.uuidString
            return row
        })
        let tracks = try! JSONDecoder().decode([MixtapeTrackDTO].self, from: data)
        return MixtapeDetailDTO(mixtape: tape, tracks: tracks)
    }

    /// A playlist for the landscape vinyl shelf: every cover is real iTunes art.
    static let vinylPlaylist = UnifiedPlaylist(
        key: "spotify:37i9dQZF1DX4sWSpwq3LiO", providerID: .spotify, playlistID: "37i9dQZF1DX4sWSpwq3LiO",
        name: "EUPHORIC", description: "sunrise on the chair, first tracks of the day",
        image: URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/f2/47/06/f24706bc-a90c-f730-bd8a-586ddde8af3e/829299184631.jpg/600x600bb.jpg"),
        trackCount: 11, owner: "zlichtman", contentRevision: "fixture"
    )

    static func vinylTracks() -> [UnifiedTrack] {
        let rows: [(String, String, String, String, Int, ProviderID)] = [
            ("Motion Sickness", "Phoebe Bridgers", "Stranger in the Alps", "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/20/4c/6e/204c6ef3-8e95-4cee-2256-202ca62aebed/60220.jpg/600x600bb.jpg", 229760, .spotify),
            ("Chamber of Reflection", "Mac DeMarco", "Salad Days", "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/e0/04/eb/e004eb2b-754f-4a76-9ecc-87d4eea2a327/cover.jpg/600x600bb.jpg", 231724, .apple),
            ("Sofia", "Clairo", "Immunity", "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/f2/47/06/f24706bc-a90c-f730-bd8a-586ddde8af3e/829299184631.jpg/600x600bb.jpg", 188387, .spotify),
            ("Apocalypse", "Cigarettes After Sex", "Cigarettes After Sex", "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/b3/5e/0f/b35e0fbe-2370-fc48-0f0c-977525e93bf2/720841214601_Cover.jpg/600x600bb.jpg", 290147, .apple),
            ("Northern Attitude", "Noah Kahan", "Stick Season", "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/ad/6b/4c/ad6b4cab-ef20-9dbf-e24e-f4b81118c86a/23UM1IM22838.rgb.jpg/600x600bb.jpg", 267256, .spotify),
            ("Dreams", "Fleetwood Mac", "Rumours", "https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/d2/48/f4/d248f4ae-a7e4-a48e-1588-6617de3e8d76/mzi.izeorbmm.jpg/600x600bb.jpg", 254453, .apple),
            ("Nothing in This Town", "The Dig", "Electric Toys", "https://is1-ssl.mzstatic.com/image/thumb/Music126/v4/52/d3/b3/52d3b368-9ecf-df11-f67e-532c3eeb7c93/192562274798_cover.jpg/600x600bb.jpg", 274497, .spotify),
            ("Beginning to Blue", "Still Corners", "Creatures of an Hour", "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/33/99/b7/3399b72f-7dce-66c5-7f60-a484ffe30770/cover.jpg/600x600bb.jpg", 191773, .apple),
            ("Catacombs", "Fog Lake", "Victoria Park", "https://is1-ssl.mzstatic.com/image/thumb/Music211/v4/6b/3d/f9/6b3df9cc-c32e-fe22-ec26-647fbd6eb97c/352011.jpg/600x600bb.jpg", 201028, .spotify),
            ("Desert Eagle", "Genevieve Stokes", "With a Lightning Bolt", "https://is1-ssl.mzstatic.com/image/thumb/Music221/v4/30/01/e8/3001e8b3-786c-bfaf-1087-5439f4bd2531/075679633767.jpg/600x600bb.jpg", 134529, .apple),
            ("Holocene", "Bon Iver", "Bon Iver", "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/87/0e/b1/870eb1eb-da2e-a51b-1ed2-3cac0e8fdd95/789577237896.png/600x600bb.jpg", 212960, .spotify),
        ]
        return rows.enumerated().map { offset, row in
            let id = "fixture-\(offset)"
            return UnifiedTrack(
                key: "\(row.5.rawValue):\(id)", providerID: row.5, providerTrackID: id,
                uri: row.5 == .spotify ? "spotify:track:\(id)" : "apple:song:\(id)",
                name: row.0, artists: [UnifiedArtist(id: "a-\(offset)", name: row.1)],
                album: row.2, albumArt: URL(string: row.3), durationMs: row.4
            )
        }
    }

    private static func track(_ uri: String, _ name: String, _ artist: String, _ art: String, _ duration: Int,
                              note: String? = nil, photo: String? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "id": UUID().uuidString, "track_uri": uri, "track_name": name, "artist": artist,
            "album_art": art, "duration_ms": duration, "skip_regions": [],
        ]
        if let note { row["note"] = note }
        if let photo { row["note_image_url"] = photo }
        return row
    }
}
/// Render the editor as a pushed screen, just like opening a saved mixtape.
/// A navigation root omits Back and gives the toolbar different geometry.
struct ScreenshotMixtapeView: View {
    @Environment(ThemeStore.self) private var theme
    @State private var path = ["mixtape"]
    private let fixture = ScreenshotFixtures.mixtape()

    var body: some View {
        NavigationStack(path: $path) {
            theme.palette.bg.ignoresSafeArea()
                .navigationTitle("Mixtapes")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { _ in
                    MixtapeEditorView(
                        mixtapeID: fixture.mixtape.id,
                        recipientName: ScreenshotFixtures.recipientName,
                        fixture: fixture
                    )
                }
        }
        .tint(theme.palette.text)
        .preferredColorScheme(theme.current.group == .dark ? .dark : .light)
    }
}
struct ScreenshotVinylView: View {
    @Environment(ThemeStore.self) private var theme
    @State private var path = ["vinyl"]
    @State private var tracks = PlaylistTracksRepository(
        fetch: { _ in .success(ScreenshotFixtures.vinylTracks()) }, persistenceEnabled: false
    )

    var body: some View {
        NavigationStack(path: $path) {
            theme.palette.bg.ignoresSafeArea()
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { _ in
                    PlaylistDetailView(playlist: ScreenshotFixtures.vinylPlaylist, ownership: .friend)
                }
        }
        .environment(tracks)
        .tint(theme.palette.text)
        .preferredColorScheme(theme.current.group == .dark ? .dark : .light)
    }
}
#endif
