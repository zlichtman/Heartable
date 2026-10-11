import SwiftUI

/// One title/subtitle treatment for all five root pages. Pages own the spacing
/// after the header (filters, service badges, or content), not its typography.
struct HeartablePageHeader: View {
    @Environment(ThemeStore.self) private var theme
    let heading: String
    let subtitle: String?
    var action: Action? = nil

    init(tab: AppTab, action: Action? = nil) {
        self.init(title: tab.title, subtitle: tab.subtitle, action: action)
    }

    init(title: String, subtitle: String? = nil, action: Action? = nil) {
        self.heading = title
        self.subtitle = subtitle
        self.action = action
    }

    struct Action {
        let title: String
        let symbol: String
        let perform: () -> Void
        var iconOnly = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let action {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 16) {
                        title.fixedSize()
                        Spacer(minLength: 0)
                        actionButton(action).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        title
                        actionButton(action)
                    }
                }
            } else { title }
            if let subtitle {
                Text(subtitle)
                .font(Typography.body(14))
                .foregroundStyle(theme.palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: some View {
        Text(heading)
            .font(Typography.heading(32))
            .foregroundStyle(theme.palette.text)
            .accessibilityAddTraits(.isHeader)
    }

    private func actionButton(_ action: Action) -> some View {
        Button(action: action.perform) {
            Group {
                if action.iconOnly { Image(systemName: action.symbol) }
                else { Label(action.title, systemImage: action.symbol) }
            }
                .font(Typography.semibold(action.iconOnly ? 21 : 13))
                .foregroundStyle(theme.palette.rose)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .frame(minWidth: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier("pageHeader.action")
    }
}
