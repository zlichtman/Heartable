import SwiftUI

/// Shared navigation chrome for custom Heartable surfaces. Native navigation
/// stacks keep their system back button; sheets and hand-built bars use this so
/// arrow weight, color, hit target, and accessibility stay identical.
struct HeartableNavigationButton: View {
    enum Kind {
        case back
        case dismiss

        var symbol: String {
            switch self {
            case .back: "chevron.left"
            case .dismiss: "chevron.down"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .back: "Back"
            case .dismiss: "Dismiss"
            }
        }
    }

    @Environment(ThemeStore.self) private var theme

    let kind: Kind
    var accessibilityLabel: String?
    var drawsSurface = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: kind.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.palette.text)
                .frame(width: 44, height: 44)
                .background {
                    if drawsSurface {
                        Circle()
                            .fill(theme.palette.surface)
                            .overlay {
                                Circle().stroke(theme.palette.border, lineWidth: 1)
                            }
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? kind.accessibilityLabel)
    }
}
