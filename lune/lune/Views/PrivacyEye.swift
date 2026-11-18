import SwiftUI

/// The private-browsing eyes, after Arc Search's incognito toggle: two tall googly eyes whose
/// pupils glance to the side. Going private drops a lid over each eye, leaving a sleepy sliver
/// along the bottom; leaving private lifts the lids and the pupils dart back into place.
///
/// Drawn on a 24x18 grid and scaled so the width is `size`.
struct PrivacyEye: View {
    let closed: Bool
    var size: CGFloat = 24

    var body: some View {
        EyesShape(lid: closed ? 1 : 0, glance: closed ? 0.3 : 1)
            .frame(width: size, height: size * 0.75)
            .animation(
                closed
                    ? .spring(response: 0.2, dampingFraction: 0.9)
                    : .spring(response: 0.42, dampingFraction: 0.58),
                value: closed
            )
            .accessibilityHidden(true)
    }
}

private nonisolated struct EyesShape: Shape {
    /// 0 is wide awake, 1 is the lid resting low.
    var lid: CGFloat
    /// 1 is the pupil resting against the inner left edge; 0 is centred.
    var glance: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(lid, glance) }
        set { lid = newValue.first; glance = newValue.second }
    }

    private static let centerY: CGFloat = 9.4
    private static let outer = CGSize(width: 5.4, height: 8.5)
    private static let ring: CGFloat = 1.65

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for centerX in [6.15, 18.35] as [CGFloat] {
            path = path.union(eye(centerX: centerX))
        }
        let unit = rect.width / 24
        return path.applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: unit, y: unit)
        )
    }

    private func oval(_ centerX: CGFloat, _ size: CGSize) -> Path {
        Path(ellipseIn: CGRect(
            x: centerX - size.width, y: Self.centerY - size.height,
            width: size.width * 2, height: size.height * 2
        ))
    }

    private func eye(centerX: CGFloat) -> Path {
        let centerY = Self.centerY
        let inner = CGSize(width: Self.outer.width - Self.ring, height: Self.outer.height - Self.ring)
        var eye = oval(centerX, Self.outer).subtracting(oval(centerX, inner))

        // Pupil hugging the inner edge, with a catchlight punched out of it.
        let radius: CGFloat = 2.55
        let restX = centerX - inner.width + radius + 0.2
        let pupil = CGPoint(x: centerX + (restX - centerX) * glance, y: centerY + 0.5)
        let ball = Path(ellipseIn: CGRect(
            x: pupil.x - radius, y: pupil.y - radius, width: radius * 2, height: radius * 2
        ))
        let shine = Path(ellipseIn: CGRect(
            x: pupil.x - radius * 0.62, y: pupil.y - radius * 0.66, width: 1.3, height: 1.3
        ))
        eye = eye.union(ball.subtracting(shine))

        let amount = max(0, lid)
        guard amount > 0.001 else { return eye }

        // The lid fills the inner oval from the top down to a gently bowed edge and stops short
        // of the bottom, leaving a dark crescent between lid and outline. It can overshoot a
        // little while springing, which just narrows the crescent.
        let top = centerY - inner.height - 1
        let rest = centerY + inner.height - 2.5
        let edge = top + (rest - top) * amount
        var cover = Path()
        cover.move(to: CGPoint(x: centerX - inner.width - 1, y: top))
        cover.addLine(to: CGPoint(x: centerX + inner.width + 1, y: top))
        cover.addLine(to: CGPoint(x: centerX + inner.width + 1, y: edge))
        cover.addQuadCurve(
            to: CGPoint(x: centerX - inner.width - 1, y: edge),
            control: CGPoint(x: centerX, y: edge + 1.8 * min(amount, 1))
        )
        cover.closeSubpath()
        return eye.union(oval(centerX, inner).intersection(cover))
    }
}

#Preview {
    @Previewable @State var closed = false
    PrivacyEye(closed: closed, size: 120)
        .foregroundStyle(.white)
        .padding(40)
        .background(.black)
        .onTapGesture { closed.toggle() }
}
