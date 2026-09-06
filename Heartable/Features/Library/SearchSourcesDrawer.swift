import SwiftUI

/// A bounded multi-select grid, not a full-height stack of oversized action rows.
struct SearchSourcesDrawer: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.dynamicTypeSize) private var textSize
    let items: [HeartableChoiceItem]
    let onSelect: (HeartableChoiceItem) -> Void

    var body: some View {
        HeartableDrawer {
            VStack(alignment: .leading, spacing: 16) {
                Text("Search in").font(Typography.heading(23)).foregroundStyle(theme.palette.text)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10),
                                         count: textSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                    ForEach(items) { item in
                        Button { onSelect(item) } label: {
                            HStack(spacing: 8) {
                                if let id = item.providerID { ProviderLogo(id: id, size: 28) }
                                Text(item.title).font(Typography.semibold(13))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isSelected ? theme.palette.rose : theme.palette.textMuted)
                            }
                            .foregroundStyle(theme.palette.text)
                            .padding(12).frame(maxWidth: .infinity, minHeight: 56)
                            .background(theme.palette.card, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(
                                item.isSelected ? theme.palette.rose : theme.palette.border, lineWidth: 1))
                        }.buttonStyle(.plain)
                            .accessibilityValue(item.isSelected ? "Selected" : "Not selected")
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 20)
        }
    }
}
