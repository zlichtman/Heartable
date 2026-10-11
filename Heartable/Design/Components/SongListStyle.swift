import SwiftUI

enum SongListStyle: String, CaseIterable, Identifiable {
    case classic, compact, blocks, clean, linerNotes, covers
    static let storageKey = "heartable.appearance.songListStyle"
    var id: String { rawValue }
    var title: String {
        switch self { case .classic: "Classic"; case .compact: "Compact"; case .blocks: "Artwork blocks"
        case .clean: "Borderless"; case .linerNotes: "Liner notes"; case .covers: "Cover grid" }
    }
    var symbol: String {
        switch self { case .classic: "list.bullet"; case .compact: "line.3.horizontal"; case .blocks: "rectangle.grid.1x2"
        case .clean: "list.bullet.below.rectangle"; case .linerNotes: "text.alignleft"; case .covers: "square.grid.2x2" }
    }
    var artworkSize: CGFloat {
        switch self { case .classic, .clean: 48; case .compact: 32; case .blocks: 72; case .linerNotes: 0; case .covers: 140 }
    }
    var verticalPadding: CGFloat { self == .compact ? 3 : self == .blocks ? 12 : 6 }
}

struct SongListRowSurface: ViewModifier {
    @Environment(ThemeStore.self) private var theme
    let style: SongListStyle
    var enclosed = false
    private var hasCard: Bool { style == .blocks || (enclosed && (style == .classic || style == .compact)) }
    func body(content: Content) -> some View {
        content
            .frame(minHeight: 44)
            .padding(.vertical, style.verticalPadding)
            .padding(.horizontal, hasCard ? 12 : 0)
            .background(hasCard ? theme.palette.card : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay {
                if hasCard {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(theme.palette.border, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}
