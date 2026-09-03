import SwiftUI

/// One title/subtitle treatment for all five root pages. Pages own the spacing
/// after the header (filters, service badges, or content), not its typography.
struct HeartablePageHeader: View {
    @Environment(ThemeStore.self) private var theme
    let tab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tab.title)
                .font(Typography.heading(32))
                .foregroundStyle(theme.palette.text)
                .accessibilityAddTraits(.isHeader)
            Text(tab.subtitle)
                .font(Typography.body(14))
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
