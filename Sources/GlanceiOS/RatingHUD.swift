//
//  RatingHUD.swift
//  Glance (iPhone / iPad)
//

import SwiftUI

// MARK: - Trash bin (a wire-mesh bin like the classic Mac one; its opening glows red when the photo will be dropped)

private struct BinBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * 0.14))
        path.addLine(to: CGPoint(x: w, y: h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.91, y: h * 0.93))
        path.addQuadCurve(to: CGPoint(x: w * 0.09, y: h * 0.93), control: CGPoint(x: w * 0.5, y: h * 1.04))
        path.closeSubpath()
        return path
    }
}

struct TrashBin: View {
    /// 0…1: how far the photo has been pulled; 1 = release now to drop it in.
    var progress: CGFloat
    var ready: Bool

    static let size = CGSize(width: 98, height: 114)

    var body: some View {
        let w = Self.size.width, h = Self.size.height
        ZStack(alignment: .top) {
            // Soft contact shadow on the "floor".
            Ellipse().fill(Color.black.opacity(0.32)).frame(width: w * 0.9, height: 14).blur(radius: 5).offset(y: h - 8)

            // Body: brushed metal with a wire mesh.
            BinBodyShape()
                .fill(LinearGradient(stops: [
                    .init(color: Color(white: 0.58), location: 0),
                    .init(color: Color(white: 0.90), location: 0.22),
                    .init(color: Color(white: 0.68), location: 0.55),
                    .init(color: Color(white: 0.84), location: 0.80),
                    .init(color: Color(white: 0.52), location: 1)], startPoint: .leading, endPoint: .trailing))
                .overlay {
                    Canvas { context, size in
                        context.clip(to: BinBodyShape().path(in: CGRect(origin: .zero, size: size)))
                        var mesh = Path()
                        let step: CGFloat = 12
                        var x = -size.height
                        while x < size.width + size.height {
                            mesh.move(to: CGPoint(x: x, y: size.height * 0.14))
                            mesh.addLine(to: CGPoint(x: x + size.height * 0.8, y: size.height))
                            mesh.move(to: CGPoint(x: x + size.height * 0.8, y: size.height * 0.14))
                            mesh.addLine(to: CGPoint(x: x, y: size.height))
                            x += step
                        }
                        context.stroke(mesh, with: .color(Color.black.opacity(0.28)), lineWidth: 1)
                    }
                }
                .overlay(BinBodyShape().stroke(Color.black.opacity(0.35), lineWidth: 1))
                .frame(width: w, height: h)

            // Opening: dark inside, rim on top; red glow when ready.
            ZStack {
                Ellipse().fill(LinearGradient(colors: [Color(white: 0.06), Color(white: 0.30)],
                                              startPoint: .top, endPoint: .bottom))
                Ellipse().fill(Color.red.opacity(ready ? 0.62 : 0.0))
                Ellipse().stroke(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.55)],
                                                startPoint: .top, endPoint: .bottom), lineWidth: 3.5)
            }
            .frame(width: w, height: h * 0.26)
            .offset(y: h * 0.01)
        }
        .frame(width: w, height: h)
        .shadow(color: ready ? Color.red.opacity(0.55) : .clear, radius: 20)
        .rotationEffect(.degrees(ready ? -4 : 0), anchor: .bottom)
        .scaleEffect(ready ? 1.12 : 0.9 + 0.1 * progress, anchor: .bottom)
        .animation(.spring(duration: 0.28, bounce: 0.45), value: ready)
    }
}

/// The only thing on screen besides the photo while it is pulled down: the bin rises from the bottom edge.
struct TrashRiseHUD: View {
    @ObservedObject var model: RatingDragModel

    private var progress: CGFloat { min(max(-model.offset / 104, 0), 1) }
    private var ready: Bool { progress >= 1 }
    private static let bottomGap: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let binHeight = TrashBin.size.height
            let restingTop = proxy.size.height - proxy.safeAreaInsets.bottom - Self.bottomGap - binHeight
            TrashBin(progress: progress, ready: ready)
                .position(x: proxy.size.width / 2, y: restingTop + binHeight / 2 + (1 - progress) * 150)
                .opacity(Double(min(1, progress * 2.5)))
                .onAppear { report(proxy, restingTop) }
                .onChange(of: proxy.size) { _, _ in report(proxy, restingTop) }
        }
        .ignoresSafeArea()
        .opacity(model.offset < 0 ? 1 : 0)
        .sensoryFeedback(.impact(weight: .medium), trigger: ready)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The photo flies to the opening of the bin.
    private func report(_ proxy: GeometryProxy, _ restingTop: CGFloat) {
        let frame = proxy.frame(in: .global)
        model.trashCenter = CGPoint(x: frame.midX, y: frame.minY + restingTop + TrashBin.size.height * 0.14)
    }
}

// MARK: - Stars (a row that rises as the photo is pulled up; only the star the finger is actually on is chosen)

extension RatingDragModel {
    /// 1…count are the stars. nil = the finger is not on the row, so releasing cancels.
    static func slot(x: CGFloat, y: CGFloat, count: Int, screenWidth: CGFloat) -> Int? {
        guard abs(y - bandCenter) <= bandHalfHeight, screenWidth > 0 else { return nil }
        let inset = StarRiseHUD.sideInset
        let usable = max(screenWidth - inset * 2, 1)
        let relative = (x * screenWidth - inset) / usable
        return min(max(Int(relative * CGFloat(count)), 0), count - 1) + 1
    }
}

struct StarRiseHUD: View {
    /// Space between the screen edge and the star row: the finger-to-slot mapping depends on it.
    static let sideInset: CGFloat = 18

    @ObservedObject var model: RatingDragModel
    var count: Int

    private var progress: CGFloat { min(max(model.offset / 60, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let slot = RatingDragModel.slot(x: model.fingerX, y: model.fingerY, count: count, screenWidth: width)
            let lit = slot ?? 0
            HStack(spacing: 0) {
                ForEach(1...count, id: \.self) { index in
                    let on = index <= lit
                    Image(systemName: on ? "star.fill" : "star")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(on ? AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 1, green: 0.86, blue: 0.3), Color(red: 1, green: 0.62, blue: 0.1)],
                            startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.primary.opacity(0.5)))
                        .scaleEffect(index == slot ? 1.36 : (on ? 1.06 : 0.94))
                        .offset(y: index == slot ? -6 : 0)
                        .shadow(color: on ? Color.orange.opacity(0.45) : .clear, radius: index == slot ? 12 : 3)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 82)
            .glassSurface(.capsule)
            .padding(.horizontal, Self.sideInset)
            .opacity(slot == nil ? 0.78 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.45), value: slot)
            .frame(width: width)
            .position(x: width / 2, y: proxy.size.height * RatingDragModel.bandCenter)
            .opacity(Double(progress))
            .scaleEffect(0.94 + 0.06 * progress)
            .onAppear { model.screenWidth = width }
            .onChange(of: width) { _, new in model.screenWidth = new }
        }
        .opacity(model.offset > 0 ? 1 : 0)
        .sensoryFeedback(.selection, trigger: RatingDragModel.slot(x: model.fingerX, y: model.fingerY, count: count,
                                                                      screenWidth: model.screenWidth))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
