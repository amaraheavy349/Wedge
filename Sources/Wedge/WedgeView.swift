import SwiftUI

/// SwiftUI canvas that renders a pull-cord with a brass-bead handle. The cord
/// hangs from the menubar anchor and the handle follows the cursor. The cord
/// itself sags with gravity and stretches taut as it's pulled longer.
/// Coordinates are local to the host view, SwiftUI top-left origin.
struct WedgeView: View {
    let anchor: CGPoint
    let tip: CGPoint
    let isOn: Bool
    /// 0...1 — how close we are to the commit threshold. Used to brighten the
    /// bead as the user nears the click point.
    let armProgress: Double

    private static let cordBase     = Color(red: 0.14, green: 0.13, blue: 0.13)
    private static let cordMid      = Color(red: 0.36, green: 0.31, blue: 0.27)
    private static let cordHi       = Color(red: 0.78, green: 0.71, blue: 0.60)

    private static let beadShadow   = Color(red: 0.10, green: 0.07, blue: 0.03)
    private static let beadBase     = Color(red: 0.55, green: 0.36, blue: 0.10)
    private static let beadHi       = Color(red: 1.00, green: 0.86, blue: 0.52)
    private static let beadArmed    = Color(red: 1.00, green: 0.78, blue: 0.20)

    var body: some View {
        Canvas { context, _ in
            let dx = tip.x - anchor.x
            let dy = tip.y - anchor.y
            let length = max(1, hypot(dx, dy))

            // Catenary-ish sag: control point pulled down by gravity, but
            // less so as the cord pulls taut.
            let sag = max(0, min(28, length * 0.10 - max(0, (length - 40) * 0.04)))
            let mid = CGPoint(x: (anchor.x + tip.x) / 2, y: (anchor.y + tip.y) / 2)
            let control = CGPoint(x: mid.x, y: mid.y + sag)

            // Perpendicular for offset highlights.
            let perp = unitPerpendicular(from: anchor, to: tip)

            // 1) Soft drop shadow under the cord.
            let shadowOffset = CGPoint(x: 0.8, y: 2.0)
            let shadowPath = curve(
                from: anchor.offset(shadowOffset),
                through: control.offset(shadowOffset),
                to: tip.offset(shadowOffset)
            )
            context.stroke(
                shadowPath,
                with: .color(.black.opacity(0.45)),
                style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
            )

            // 2) Base (darkest, full thickness).
            let basePath = curve(from: anchor, through: control, to: tip)
            context.stroke(
                basePath,
                with: .color(Self.cordBase),
                style: StrokeStyle(lineWidth: 3.4, lineCap: .round)
            )

            // 3) Mid stripe to give it body.
            let midOffset = CGPoint(x: -perp.x * 0.5, y: -perp.y * 0.5)
            let midPath = curve(
                from: anchor.offset(midOffset),
                through: control.offset(midOffset),
                to: tip.offset(midOffset)
            )
            context.stroke(
                midPath,
                with: .color(Self.cordMid),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
            )

            // 4) Top sheen — thin bright stripe.
            let sheenOffset = CGPoint(x: -perp.x * 1.1, y: -perp.y * 1.1)
            let sheenPath = curve(
                from: anchor.offset(sheenOffset),
                through: control.offset(sheenOffset),
                to: tip.offset(sheenOffset)
            )
            context.stroke(
                sheenPath,
                with: .color(Self.cordHi.opacity(0.7)),
                style: StrokeStyle(lineWidth: 0.7, lineCap: .round)
            )

            // 5) The brass bead at the tip — only after it's actually pulled.
            if length > 10 {
                drawBead(at: tip, in: context)
            }
        }
        .allowsHitTesting(false)
    }

    private func curve(from a: CGPoint, through c: CGPoint, to b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: b, control: c)
        return p
    }

    private func unitPerpendicular(from a: CGPoint, to b: CGPoint) -> CGPoint {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = max(0.0001, hypot(dx, dy))
        return CGPoint(x: dy / len, y: -dx / len)
    }

    private func drawBead(at tip: CGPoint, in context: GraphicsContext) {
        let outer: CGFloat = 9
        let outerRect = CGRect(x: tip.x - outer, y: tip.y - outer, width: outer * 2, height: outer * 2)

        // Soft shadow underneath the bead.
        context.fill(
            Path(ellipseIn: outerRect.offsetBy(dx: 0.6, dy: 2.6)),
            with: .color(.black.opacity(0.5))
        )

        // Dark outer ring.
        context.fill(
            Path(ellipseIn: outerRect),
            with: .color(Self.beadShadow)
        )

        // Brass body — brighter as the user nears the commit threshold.
        let innerRect = outerRect.insetBy(dx: 1.6, dy: 1.6)
        let armColor = Color.blend(Self.beadBase, Self.beadArmed, t: armProgress)
        let gradient = Gradient(stops: [
            .init(color: Self.beadHi, location: 0.0),
            .init(color: armColor, location: 0.5),
            .init(color: Self.beadShadow, location: 1.0)
        ])
        context.fill(
            Path(ellipseIn: innerRect),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: innerRect.midX, y: innerRect.minY),
                endPoint: CGPoint(x: innerRect.midX, y: innerRect.maxY)
            )
        )

        // Specular highlight crescent (top-left).
        let sheenRect = innerRect.insetBy(dx: 2.4, dy: 2.4).offsetBy(dx: -1.4, dy: -1.4)
        context.fill(
            Path(ellipseIn: sheenRect),
            with: .color(.white.opacity(0.55))
        )

        // Armed glow halo when committed threshold is crossed.
        if armProgress >= 1.0 {
            context.stroke(
                Path(ellipseIn: outerRect.insetBy(dx: -2, dy: -2)),
                with: .color(Self.beadArmed.opacity(0.55)),
                lineWidth: 2.5
            )
        }

        // Crisp ring inside the bead to give it a metallic feel.
        context.stroke(
            Path(ellipseIn: innerRect.insetBy(dx: 0.6, dy: 0.6)),
            with: .color(.black.opacity(0.35)),
            lineWidth: 0.6
        )
    }
}

private extension CGPoint {
    func offset(_ p: CGPoint) -> CGPoint {
        CGPoint(x: x + p.x, y: y + p.y)
    }
}

private extension Color {
    /// Linearly interpolates two Colors in sRGB space. Cheap good-enough blend.
    static func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        let clamped = max(0, min(1, t))
        let ns1 = NSColor(a).usingColorSpace(.sRGB) ?? .black
        let ns2 = NSColor(b).usingColorSpace(.sRGB) ?? .black
        return Color(
            red:   ns1.redComponent   + (ns2.redComponent   - ns1.redComponent)   * clamped,
            green: ns1.greenComponent + (ns2.greenComponent - ns1.greenComponent) * clamped,
            blue:  ns1.blueComponent  + (ns2.blueComponent  - ns1.blueComponent)  * clamped
        )
    }
}
