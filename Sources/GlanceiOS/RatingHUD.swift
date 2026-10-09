//
//  RatingHUD.swift
//  Glance (iPhone / iPad)
//

import SwiftUI

// MARK: - Trash can (drawn, with a lid that opens as the photo is pulled down)

private struct TrashBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.10, y: h * 0.28))
        path.addLine(to: CGPoint(x: w * 0.90, y: h * 0.28))
        path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.90))
        path.addQuadCurve(to: CGPoint(x: w * 0.74, y: h * 0.98), control: CGPoint(x: w * 0.81, y: h * 0.98))
        path.addLine(to: CGPoint(x: w * 0.26, y: h * 0.98))
        path.addQuadCurve(to: CGPoint(x: w * 0.18, y: h * 0.90), control: CGPoint(x: w * 0.19, y: h * 0.98))
        path.closeSubpath()
        return path
    }
}

private struct TrashRibs: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [0.34, 0.50, 0.66] {
            let x = rect.width * fraction
            path.move(to: CGPoint(x: x, y: rect.height * 0.42))
            path.addLine(to: CGPoint(x: x, y: rect.height * 0.82))
        }
        return path
    }
}

/// A trash can whose lid swings open: `lidOpen` 0 (closed) … 1 (wide open).
struct TrashCanIcon: View {
    var lidOpen: Double
    var color: Color = .white

    var body: some View {
        ZStack {
            TrashBodyShape().fill(color.opacity(0.16))
            TrashBodyShape().stroke(color, style: StrokeStyle(lineWidth: 3.2, lineJoin: .round))
            TrashRibs().stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // Lid + handle, hinged on its left end.
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(color, style: StrokeStyle(lineWidth: 3.2))
                        .frame(width: w * 0.30, height: h * 0.10)
                        .offset(x: w * 0.35, y: -h * 0.07)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: w * 0.96, height: h * 0.10)
                        .offset(x: w * 0.02, y: h * 0.18)
                }
                .frame(width: w, height: h, alignment: .topLeading)
                .rotationEffect(.degrees(-46 * lidOpen), anchor: UnitPoint(x: 0.02, y: 0.28))
            }
        }
        .frame(width: 58, height: 66)
        .animation(.spring(duration: 0.25, bounce: 0.35), value: lidOpen)
    }
}

/// The trash that rises from the bottom edge as the photo is pulled down.
struct TrashRiseHUD: View {
    @ObservedObject var model: RatingDragModel

    private var progress: CGFloat { min(max(-model.offset / 104, 0), 1) }
    private var ready: Bool { progress >= 1 }

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 10) {
                TrashCanIcon(lidOpen: ready ? 1 : Double(progress) * 0.55,
                             color: ready ? .white : .primary)
                    .frame(width: 112, height: 112)
                    .glassSurface(.circle, tint: ready ? Color.red.opacity(0.85) : nil)
                    .scaleEffect(ready ? 1.14 : 0.8 + 0.2 * progress)
                    .shadow(color: (ready ? Color.red : Color.black).opacity(0.25 * progress), radius: 18, y: 8)
                Text(ready ? "松手丢弃" : "继续下拉")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .glassSurface(.capsule, tint: ready ? Color.red.opacity(0.7) : nil)
                    .foregroundStyle(ready ? Color.white : Color.primary)
            }
            .offset(y: (1 - progress) * 230)
            .opacity(Double(min(1, progress * 2.4)))
            .padding(.bottom, 56)
        }
        .opacity(model.offset < 0 ? 1 : 0)
        .animation(.spring(duration: 0.28, bounce: 0.3), value: ready)
        .sensoryFeedback(.impact(weight: .medium), trigger: ready)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Stars (a row that rises as the photo is pulled up; only the star the finger is actually on is chosen)

extension RatingDragModel {
    /// Slot 0 is "clear the rating", 1…count are the stars. nil = the finger is not on the row, so releasing cancels.
    static func slot(x: CGFloat, y: CGFloat, count: Int, screenWidth: CGFloat) -> Int? {
        guard abs(y - bandCenter) <= bandHalfHeight, screenWidth > 0 else { return nil }
        let inset = StarRiseHUD.sideInset
        let usable = max(screenWidth - inset * 2, 1)
        let slots = count + 1
        let relative = (x * screenWidth - inset) / usable
        return min(max(Int(relative * CGFloat(slots)), 0), slots - 1)
    }
}

struct StarRiseHUD: View {
    /// Space between the screen edge and the star row: the finger-to-slot mapping depends on it.
    static let sideInset: CGFloat = 18

    @ObservedObject var model: RatingDragModel
    var count: Int
    /// The photo's current rating, shown so a re-rate is not a surprise.
    var current: Int

    private var progress: CGFloat { min(max(model.offset / 60, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let slot = RatingDragModel.slot(x: model.fingerX, y: model.fingerY, count: count, screenWidth: width)
            let lit = max(slot ?? 0, 0)
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    // Slot 0: clear the rating.
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(slot == 0 ? Color.red : Color.primary.opacity(0.5))
                        .scaleEffect(slot == 0 ? 1.25 : 1)
                        .frame(maxWidth: .infinity)
                    ForEach(1...count, id: \.self) { index in
                        let on = index <= lit
                        Image(systemName: on ? "star.fill" : "star")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(on ? AnyShapeStyle(LinearGradient(
                                colors: [Color(red: 1, green: 0.86, blue: 0.3), Color(red: 1, green: 0.62, blue: 0.1)],
                                startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.primary.opacity(0.45)))
                            .scaleEffect(index == slot ? 1.34 : (on ? 1.05 : 0.95))
                            .offset(y: index == slot ? -6 : 0)
                            .shadow(color: on ? Color.orange.opacity(0.45) : .clear, radius: index == slot ? 12 : 3)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 0)
                .frame(height: 78)
                .glassSurface(.capsule)
                .padding(.horizontal, Self.sideInset)

                Text(hint(for: slot))
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .glassSurface(.capsule)
                    .foregroundStyle(slot == nil ? Color.secondary : Color.primary)
            }
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

    private func hint(for slot: Int?) -> String {
        switch slot {
        case nil: return "滑到星星上再松手；离开星星松手＝取消"
        case 0: return "松手清除评分"
        case let n?: return "松手评 \(n) 星"
        }
    }
}
