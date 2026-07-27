import SwiftUI

/// A brand-native startup treatment that does not impersonate the selected
/// alternate app icon. The native launch screen supplies the same dark canvas;
/// this view takes over once SwiftUI is ready and animates without loading any
/// remote state or delaying authentication.
struct HeartableLaunchAnimation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeights: [CGFloat] = [18, 30, 42, 54, 42, 30, 18]

    var body: some View {
        VStack(spacing: 22) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
                let time = context.date.timeIntervalSinceReferenceDate

                ZStack {
                    Capsule()
                        .fill(Color(hex: 0xe8457c, alpha: 0.16))
                        .frame(width: 124, height: 64)
                        .blur(radius: 18)

                    HStack(alignment: .center, spacing: 6) {
                        ForEach(barHeights.indices, id: \.self) { index in
                            let pulse: CGFloat = reduceMotion
                                ? 0.72
                                : 0.58 + 0.42 * CGFloat(
                                    sin(time * 4.2 - Double(index) * 0.62)
                                )

                            Capsule()
                                .fill(
                                    index == barHeights.count / 2
                                        ? Color(hex: 0xe8457c)
                                        : Color(hex: 0xfff0e8, alpha: 0.86)
                                )
                                .frame(
                                    width: index == barHeights.count / 2 ? 7 : 5,
                                    height: max(10, barHeights[index] * pulse)
                                )
                        }
                    }
                    .frame(width: 124, height: 64)
                }
                .frame(width: 150, height: 82)
            }

            Text("Heartable")
                .font(Typography.heading(30))
                .foregroundStyle(Color(hex: 0xfff0e8))
                .tracking(-0.4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heartable is opening")
    }
}
