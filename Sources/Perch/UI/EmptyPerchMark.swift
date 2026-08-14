import SwiftUI

struct EmptyPerchMark: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ZStack {
                    EmptyPerchBranch()
                        .stroke(
                            Color.secondary.opacity(0.62),
                            style: StrokeStyle(
                                lineWidth: max(1.5, side * 0.042),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    birdSymbol(name: "bird.fill", side: side)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

                ZStack {
                    EmptyPerchFeet()
                        .stroke(
                            style: StrokeStyle(
                                lineWidth: max(1, side * 0.025),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )

                    birdSymbol(name: "bird", side: side)
                }
                .foregroundStyle(.primary)
                .compositingGroup()
                .opacity(0.58)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .accessibilityHidden(true)
    }

    private func birdSymbol(name: String, side: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: side * 0.49, weight: .regular))
            .scaleEffect(x: -1, y: 1)
            .offset(x: side * 0.04, y: -side * 0.09)
    }
}

private struct EmptyPerchBranch: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.14, 0.63))
        path.addLine(to: point(0.86, 0.63))
        return path
    }
}

private struct EmptyPerchFeet: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.48, 0.57))
        path.addLine(to: point(0.50, 0.64))

        path.move(to: point(0.53, 0.57))
        path.addLine(to: point(0.55, 0.64))
        return path
    }
}
