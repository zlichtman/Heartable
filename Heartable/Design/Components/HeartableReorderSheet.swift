import SwiftUI

/// Editable ordering uses the same compact, fully themed drawer as choices.
/// A native List retains drag-to-reorder and VoiceOver move actions, and scrolls
/// when the content-sized detent reaches the available screen height.
struct HeartableReorderSheet<Item: Identifiable, Row: View>: View {
    @Environment(ThemeStore.self) private var theme
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 64
    @State private var headerHeight: CGFloat = 60
    let title: String
    let items: [Item]
    let onMove: (IndexSet, Int) -> Void
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(Typography.heading(23))
                .foregroundStyle(theme.palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { headerHeight = $0 }
            List {
                ForEach(items) { item in
                    row(item)
                        .foregroundStyle(theme.palette.text)
                        .frame(height: rowHeight - 8)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 18))
                        .listRowBackground(theme.palette.card)
                        .listRowSeparatorTint(theme.palette.border)
                }
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
            .contentMargins(.all, 0, for: .scrollContent)
            .environment(\.editMode, .constant(.active))
            .environment(\.defaultMinListRowHeight, rowHeight)
            .scrollContentBackground(.hidden)
        }
        .padding(.bottom, 16)
        .background(theme.palette.bg.ignoresSafeArea())
        .presentationDetents([.height(headerHeight + rowHeight * CGFloat(max(1, items.count)) + 16)])
        .heartableSheetChrome()
    }
}
