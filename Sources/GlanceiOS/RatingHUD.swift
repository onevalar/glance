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
    /// 0…1 while pulling.
    var progress: CGFloat

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
        .animation(.spring(duration: 0.28, bounce: 0.3), value: ready)
        .sensoryFeedback(.impact(weight: .medium), trigger: ready)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Stars (rise as the photo is pulled up; the star under the finger is the rating)

struct StarRiseHUD: View {
    /// 0…1 while pulling.
    var progress: CGFloat
    var count: Int
    /// Currently selected star (1…count) from the finger's horizontal position.
    var selected: Int

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(1...count, id: \.self) { index in
                        let on = index <= selected
                        Image(systemName: on ? "star.fill" : "star")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(on ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.3),
                                                                                        Color(red: 1, green: 0.62, blue: 0.1)],
                                                                               startPoint: .top, endPoint: .bottom))
                                                : AnyShapeStyle(Color.primary.opacity(0.55)))
                            .scaleEffect(index == selected ? 1.34 : (on ? 1.06 : 0.94))
                            .offset(y: index == selected ? -6 : 0)
                            .shadow(color: on ? Color.orange.opacity(0.5) : .clear, radius: index == selected ? 12 : 4)
                            .frame(maxWidth: .infinity)
                            .animation(.spring(duration: 0.22, bounce: 0.5), value: selected)
                    }
                }
                .padding(.vertical, 18)
                .padding(.horizontal, 6)
                .glassSurface(.capsule)

                Text("\(selected) 星")
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .glassSurface(.capsule)
            }
            .padding(.horizontal, 12)
            .frame(width: proxy.size.width)
            .offset(y: proxy.size.height * 0.30 + (1 - progress) * 90)
            .opacity(Double(min(1, progress * 2.4)))
            .scaleEffect(0.92 + 0.08 * progress)
        }
        .sensoryFeedback(.selection, trigger: selected)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
