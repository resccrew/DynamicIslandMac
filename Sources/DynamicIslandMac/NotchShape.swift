import SwiftUI

/// The island silhouette, drawn to read as a continuation of the hardware notch.
///
/// Two things make it look "Apple" rather than like a plain rounded rectangle:
///
/// 1. **Concave top fillets.** The sides don't meet the top edge of the display
///    at a hard 90°; they flare outward along a concave curve that eases the
///    boundary back into the horizontal screen edge, the way the bottom corners
///    of the real notch do.
/// 2. **Lamé-curve (superellipse) corners.** Corners are sampled from
///    |x/r|^n + |y/r|^n = 1 rather than from a circular arc, so curvature is
///    continuous instead of jumping from straight to fixed-radius — this is the
///    "squircle" treatment Apple uses throughout its hardware and UI.
struct NotchShape: Shape {
    /// Radius of the concave blend where the sides meet the top edge.
    var topFillet: CGFloat
    /// Radius of the rounded bottom corners.
    var bottomRadius: CGFloat
    /// Lamé exponent for the bottom corners (2 is circular; higher is squarer/smoother).
    var bottomExponent: CGFloat = 5
    /// Lamé exponent for the concave fillets. Kept near-circular: the blend is
    /// small, and pushing it far from 2 makes the flare read as a step.
    var topExponent: CGFloat = 2.2
    /// The collapsed pill and idle state read fine flush against the screen
    /// edge (`false`, the default) — that's the notch-continuation look. The
    /// expanded card is much taller and, at that scale, the same flush top
    /// just reads as a flat, unrounded corner rather than a subtle blend, so
    /// it opts into an ordinary convex top corner instead.
    var topIsConvex: Bool = false

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topFillet, bottomRadius) }
        set {
            topFillet = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        topIsConvex ? convexPath(in: rect) : concavePath(in: rect)
    }

    /// Ordinary rounded-rect corners on all four sides (used by the expanded card).
    private func convexPath(in rect: CGRect) -> Path {
        var path = Path()

        var topRadius = max(0, min(topFillet, rect.width / 2))
        var bottomR = max(0, min(bottomRadius, rect.width / 2))
        let verticalOverflow = topRadius + bottomR
        if verticalOverflow > rect.height, verticalOverflow > 0 {
            let scale = rect.height / verticalOverflow
            topRadius *= scale
            bottomR *= scale
        }

        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        path.move(to: CGPoint(x: left, y: top + topRadius))

        appendLame(
            to: &path,
            center: CGPoint(x: left + topRadius, y: top + topRadius),
            radius: topRadius,
            from: CGVector(dx: -1, dy: 0),
            to: CGVector(dx: 0, dy: -1),
            exponent: topExponent
        )

        path.addLine(to: CGPoint(x: right - topRadius, y: top))

        appendLame(
            to: &path,
            center: CGPoint(x: right - topRadius, y: top + topRadius),
            radius: topRadius,
            from: CGVector(dx: 0, dy: -1),
            to: CGVector(dx: 1, dy: 0),
            exponent: topExponent
        )

        path.addLine(to: CGPoint(x: right, y: bottom - bottomR))

        appendLame(
            to: &path,
            center: CGPoint(x: right - bottomR, y: bottom - bottomR),
            radius: bottomR,
            from: CGVector(dx: 1, dy: 0),
            to: CGVector(dx: 0, dy: 1),
            exponent: bottomExponent
        )

        path.addLine(to: CGPoint(x: left + bottomR, y: bottom))

        appendLame(
            to: &path,
            center: CGPoint(x: left + bottomR, y: bottom - bottomR),
            radius: bottomR,
            from: CGVector(dx: 0, dy: 1),
            to: CGVector(dx: -1, dy: 0),
            exponent: bottomExponent
        )

        path.closeSubpath()
        return path
    }

    /// Flush concave top blending into the screen edge (collapsed pill, idle).
    private func concavePath(in rect: CGRect) -> Path {
        var path = Path()

        let fillet = max(0, min(topFillet, rect.width / 2, rect.height))
        let bodyHalfWidth = rect.width / 2 - fillet
        let radius = max(0, min(bottomRadius, bodyHalfWidth, rect.height - fillet))

        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        path.move(to: CGPoint(x: left, y: top))

        // Left concave fillet: screen edge -> left side of the body. Its center
        // sits outside and below the corner so the curve leaves the screen edge
        // horizontally and arrives at the body's side vertically; centering it
        // on the edge instead swaps those tangents and produces a visible ledge.
        appendLame(
            to: &path,
            center: CGPoint(x: left, y: top + fillet),
            radius: fillet,
            from: CGVector(dx: 0, dy: -1),
            to: CGVector(dx: 1, dy: 0),
            exponent: topExponent
        )

        path.addLine(to: CGPoint(x: left + fillet, y: bottom - radius))

        // Bottom-left squircle corner.
        appendLame(
            to: &path,
            center: CGPoint(x: left + fillet + radius, y: bottom - radius),
            radius: radius,
            from: CGVector(dx: -1, dy: 0),
            to: CGVector(dx: 0, dy: 1),
            exponent: bottomExponent
        )

        path.addLine(to: CGPoint(x: right - fillet - radius, y: bottom))

        // Bottom-right squircle corner.
        appendLame(
            to: &path,
            center: CGPoint(x: right - fillet - radius, y: bottom - radius),
            radius: radius,
            from: CGVector(dx: 0, dy: 1),
            to: CGVector(dx: 1, dy: 0),
            exponent: bottomExponent
        )

        path.addLine(to: CGPoint(x: right - fillet, y: top + fillet))

        // Right concave fillet: body side -> screen edge (mirror of the left).
        appendLame(
            to: &path,
            center: CGPoint(x: right, y: top + fillet),
            radius: fillet,
            from: CGVector(dx: -1, dy: 0),
            to: CGVector(dx: 0, dy: -1),
            exponent: topExponent
        )

        path.closeSubpath()
        return path
    }

    /// Traces a quarter of a Lamé curve from `center + radius * from` to
    /// `center + radius * to`, bulging toward the corner the two directions span.
    private func appendLame(
        to path: inout Path,
        center: CGPoint,
        radius: CGFloat,
        from dirA: CGVector,
        to dirB: CGVector,
        exponent: CGFloat,
        samples: Int = 28
    ) {
        guard radius > 0 else { return }
        let power = 2 / exponent

        for step in 0...samples {
            let theta = (CGFloat(step) / CGFloat(samples)) * (.pi / 2)
            let a = pow(cos(theta), power)
            let b = pow(sin(theta), power)
            path.addLine(to: CGPoint(
                x: center.x + radius * (a * dirA.dx + b * dirB.dx),
                y: center.y + radius * (a * dirA.dy + b * dirB.dy)
            ))
        }
    }
}
