import SwiftUI

/// A cassette drawn around a mixtape's cover. The cover is the label art, a
/// paper strip carries the side and title, and the reels turn while the tape
/// plays. The shell uses theme tokens; the label strip is always cream paper.
struct MixtapeCassette<Cover: View>: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let minutes: Int
    let isPlaying: Bool
    /// Shows the change-cover badge on the label.
    var editable = false
    @ViewBuilder let cover: () -> Cover

    /// Dark ink for the cream paper strip, which is light in every theme.
    private static var ink: Color { Color(red: 0.17, green: 0.12, blue: 0.10) }
    /// Magnetic tape wound on the reels.
    private static var tape: Color { Color(red: 0.25, green: 0.17, blue: 0.13) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .top) {
                shell(w: w)
                label(w: w, h: h)
                    .padding(.top, h * 0.065)
                plate(w: w, h: h)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                screws(w: w, h: h)
            }
        }
        .aspectRatio(1.58, contentMode: .fit)
        .shadow(color: .black.opacity(0.32), radius: 22, y: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cassette: \(title)")
    }

    // MARK: Shell

    private func shell(w: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
        return shape
            .fill(theme.palette.card)
            .overlay(
                shape.fill(LinearGradient(
                    colors: [.white.opacity(0.07), .clear],
                    startPoint: .top, endPoint: .center
                ))
            )
            .overlay(shape.stroke(theme.palette.border, lineWidth: 1))
    }

    private func screws(w: CGFloat, h: CGFloat) -> some View {
        let d = w * 0.026
        let inset = w * 0.032
        return ZStack {
            ForEach(0..<4, id: \.self) { i in
                screw(d)
                    .position(
                        x: i % 2 == 0 ? inset : w - inset,
                        y: i < 2 ? inset : h - inset
                    )
            }
        }
        .frame(width: w, height: h)
    }

    private func screw(_ d: CGFloat) -> some View {
        Circle()
            .fill(theme.palette.border)
            .frame(width: d, height: d)
            .overlay(
                Capsule()
                    .fill(theme.palette.bg.opacity(0.7))
                    .frame(width: d * 0.7, height: d * 0.16)
                    .rotationEffect(.degrees(35))
            )
    }

    /// The lower plate with its drive holes.
    private func plate(w: CGFloat, h: CGFloat) -> some View {
        let pw = w * 0.66
        let ph = h * 0.15
        return ZStack {
            CassettePlate()
                .fill(theme.palette.bgElevated)
                .overlay(CassettePlate().stroke(theme.palette.border, lineWidth: 1))
            // Drive holes are cut through the shell, so they read dark in every theme.
            HStack(spacing: 0) {
                Circle().fill(.black.opacity(0.4)).frame(width: ph * 0.36, height: ph * 0.36)
                Spacer()
                RoundedRectangle(cornerRadius: 1.5).fill(.black.opacity(0.4)).frame(width: ph * 0.24, height: ph * 0.24)
                Spacer().frame(width: pw * 0.16)
                RoundedRectangle(cornerRadius: 1.5).fill(.black.opacity(0.4)).frame(width: ph * 0.24, height: ph * 0.24)
                Spacer()
                Circle().fill(.black.opacity(0.4)).frame(width: ph * 0.36, height: ph * 0.36)
            }
            .padding(.horizontal, pw * 0.14)
            .padding(.top, ph * 0.2)
        }
        .frame(width: pw, height: ph)
    }

    // MARK: Label

    private func label(w: CGFloat, h: CGFloat) -> some View {
        let lw = w * 0.88
        let lh = h * 0.7
        let shape = RoundedRectangle(cornerRadius: w * 0.028, style: .continuous)
        return ZStack(alignment: .top) {
            cover()
                .frame(width: lw, height: lh)
                .clipped()
            paperStrip(w: w, height: lh * 0.2)
            window(w: w, h: h)
                .padding(.top, lh * 0.42)
        }
        .frame(width: lw, height: lh)
        .clipShape(shape)
        .overlay(shape.stroke(.black.opacity(0.25), lineWidth: 0.5))
        .overlay(alignment: .bottomTrailing) {
            if editable {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.black.opacity(0.35), in: Circle())
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(8)
            }
        }
    }

    private func paperStrip(w: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: w * 0.025) {
            Text("A")
                .font(Typography.semibold(w * 0.04))
                .foregroundStyle(theme.palette.cream)
                .frame(width: height * 0.62, height: height * 0.62)
                .background(Self.ink, in: RoundedRectangle(cornerRadius: 3))
            Text(title)
                .font(Typography.heading(w * 0.052))
                .foregroundStyle(Self.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if minutes > 0 {
                Text("\(minutes) MIN")
                    .font(Typography.semibold(w * 0.03))
                    .tracking(0.8)
                    .foregroundStyle(Self.ink.opacity(0.65))
            }
        }
        .padding(.horizontal, w * 0.03)
        .frame(height: height)
        .background(theme.palette.cream)
    }

    // MARK: Window

    private func window(w: CGFloat, h: CGFloat) -> some View {
        let ww = w * 0.56
        let wh = h * 0.25
        let spinning = isPlaying && !reduceMotion
        return ZStack {
            Capsule(style: .continuous)
                .fill(.black.opacity(0.62))
                .overlay(Capsule(style: .continuous).stroke(.white.opacity(0.2), lineWidth: 1))
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !spinning)) { context in
                let angle = Angle.degrees(
                    spinning ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 360) * 90 : 0
                )
                HStack(spacing: 0) {
                    reel(diameter: wh * 0.62, pack: wh * 0.9, angle: angle)
                    Spacer()
                    reel(diameter: wh * 0.62, pack: wh * 0.66, angle: angle)
                }
                .padding(.horizontal, ww * 0.12)
            }
        }
        .frame(width: ww, height: wh)
    }

    private func reel(diameter d: CGFloat, pack: CGFloat, angle: Angle) -> some View {
        ZStack {
            Circle().fill(Self.tape).frame(width: pack, height: pack)
            Circle().fill(.white.opacity(0.92)).frame(width: d * 0.62, height: d * 0.62)
            ForEach(0..<6, id: \.self) { i in
                Capsule()
                    .fill(.black.opacity(0.55))
                    .frame(width: d * 0.07, height: d * 0.16)
                    .offset(y: -d * 0.2)
                    .rotationEffect(.degrees(Double(i) * 60))
            }
            .rotationEffect(angle)
            Circle().fill(.black.opacity(0.6)).frame(width: d * 0.16, height: d * 0.16)
        }
        .frame(width: max(d, pack), height: max(d, pack))
    }
}

/// The cassette's lower plate: narrower at the top than at the bottom.
private struct CassettePlate: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.07
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
