import SwiftUI

struct StumpShape: Shape {
    static let aspectRatio = 260.0 / 440.0

    func path(in rect: CGRect) -> Path {
        func p(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + (x - 170) / 260 * rect.width, y: rect.minY + (y - 40) / 440 * rect.height)
        }

        var path = Path()
        path.move(to: p(206, 474))
        path.addLine(to: p(394, 474))
        path.move(to: p(226, 474))
        path.addCurve(to: p(232, 376), control1: p(232, 440), control2: p(228, 404))
        path.move(to: p(374, 474))
        path.addCurve(to: p(368, 376), control1: p(368, 440), control2: p(372, 404))
        path.move(to: p(232, 376))
        path.addCurve(to: p(368, 376), control1: p(250, 356), control2: p(350, 356))
        path.addCurve(to: p(232, 376), control1: p(350, 396), control2: p(250, 396))

        path.move(to: p(272, 372))
        path.addCurve(to: p(204, 150), control1: p(262, 300), control2: p(222, 230))
        path.move(to: p(300, 368))
        path.addCurve(to: p(302, 110), control1: p(302, 290), control2: p(298, 190))
        path.move(to: p(328, 372))
        path.addCurve(to: p(396, 150), control1: p(338, 300), control2: p(378, 230))

        for (tip, angle) in [(p(204, 150), -Double.pi * 0.66), (p(302, 110), -Double.pi * 0.5), (p(396, 150), -Double.pi * 0.34)] {
            let length = 96 / 440 * rect.height
            let width = 30 / 440 * rect.height
            let end = CGPoint(x: tip.x + cos(angle) * length, y: tip.y + sin(angle) * length)
            let mid = CGPoint(x: (tip.x + end.x) / 2, y: (tip.y + end.y) / 2)
            let normal = CGPoint(x: -sin(angle) * width, y: cos(angle) * width)
            path.move(to: tip)
            path.addQuadCurve(to: end, control: CGPoint(x: mid.x + normal.x, y: mid.y + normal.y))
            path.addQuadCurve(to: tip, control: CGPoint(x: mid.x - normal.x, y: mid.y - normal.y))
        }
        return path
    }
}

struct GrowingStump: View {
    var lineWidth: Double = 2
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StumpShape()
            .trim(from: 0, to: grown ? 1 : 0)
            .stroke(.primary, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .aspectRatio(StumpShape.aspectRatio, contentMode: .fit)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.8)) { grown = true }
            }
    }
}
