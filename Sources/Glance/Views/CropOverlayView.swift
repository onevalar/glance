import SwiftUI

struct CropOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme
    let image: NSImage
    let filename: String
    let onCommit: (CGRect) -> Void
    let onCancel: () -> Void
    @State private var session: CropSession
    @State private var gestureStart: CGRect?

    init(image: NSImage, filename: String, cropRect: CGRect?, onCommit: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.image = image; self.filename = filename; self.onCommit = onCommit; self.onCancel = onCancel
        _session = State(initialValue: CropSession(rect: cropRect))
    }

    var body: some View {
        VStack(spacing: 0) {
            GlanceTitleBar {
                Text("\(filename) · 裁剪")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GlancePalette.foreground(colorScheme))
                    .lineLimit(1).truncationMode(.middle)
            } trailing: {
                Button("重置") { session.reset() }.buttonStyle(CompareChipStyle())
                Button("取消", action: onCancel).buttonStyle(CompareChipStyle()).keyboardShortcut(.cancelAction)
                Button("完成") { onCommit(session.rect) }
                    .buttonStyle(CropDoneStyle()).keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 0) {
                GeometryReader { viewport in cropCanvas(size: viewport.size) }
                    .padding(.horizontal, 48).padding(.vertical, 40)
                    .background(GlancePalette.canvas(colorScheme))
                Rectangle().fill(GlancePalette.divider(colorScheme)).frame(width: 1)
                cropInspector
            }
        }
        .font(.system(size: 13))
        .tint(GlancePalette.accent)
        .background(GlancePalette.canvas(colorScheme))
    }

    private var cropInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("裁剪").font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 8) {
                    Text("比例").foregroundStyle(.secondary)
                    Menu {
                        ForEach(CropRatio.allCases) { ratio in
                            Button {
                                session.selectRatio(ratio, imageSize: image.size)
                            } label: {
                                Text(LocalizedStringKey(ratio.rawValue))
                                if session.ratio == ratio { Image(systemName: "checkmark") }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(LocalizedStringKey(session.ratio.rawValue))
                            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 6))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GlancePalette.secondary(colorScheme))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .background(GlancePalette.buttonFill(colorScheme), in: .rect(cornerRadius: 8))
                        .contentShape(.rect(cornerRadius: 8))
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    .accessibilityLabel("裁剪比例")
                }
                Text("拖动边角调整范围，拖动框内移动。")
                    .font(.system(size: 15)).fixedSize(horizontal: false, vertical: true)
                Text("Esc 取消，完成后保存裁剪区域。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("原图始终保留").font(.system(size: 18, weight: .semibold))
                    Text("仅记录裁剪范围。重新进入裁剪可重置到原图。")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(GlancePalette.buttonFill(colorScheme), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 260)
        .background(GlancePalette.inspector(colorScheme))
    }

    private func cropCanvas(size: CGSize) -> some View {
        let frame = CropGeometry.imageFrame(imageSize: image.size, viewport: size)
        let box = session.displayRect(in: frame)
        return ZStack(alignment: .topLeading) {
            Image(nsImage: image).resizable().frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY).accessibilityHidden(true)
            CropMask(imageFrame: frame, box: box).fill(.black.opacity(0.6), style: FillStyle(eoFill: true)).allowsHitTesting(false)
            Rectangle().fill(.white.opacity(0.001)).frame(width: box.width, height: box.height)
                .contentShape(Rectangle())
                .gesture(cropGesture(frame: frame, handle: nil))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("移动裁剪区域")
                .accessibilityValue(cropValue)
                .position(x: box.midX, y: box.midY)
            CropGrid().stroke(.white.opacity(0.6), lineWidth: 1)
                .frame(width: box.width, height: box.height).position(x: box.midX, y: box.midY).allowsHitTesting(false)
            Rectangle().stroke(.white, lineWidth: 2)
                .frame(width: box.width, height: box.height).position(x: box.midX, y: box.midY).allowsHitTesting(false)
            ForEach(CropHandle.allCases, id: \.self) { handle in
                if handle.isCorner || session.ratio == .free {
                    let point = handle.point(in: box)
                    CropHandleMark(handle: handle).stroke(.white, lineWidth: 3)
                        .frame(width: 16, height: 16).shadow(color: .black.opacity(0.5), radius: 1)
                        .frame(width: 32, height: 32).contentShape(Rectangle())
                        .gesture(cropGesture(frame: frame, handle: handle))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(handle.label).accessibilityValue(cropValue)
                        .accessibilityAdjustableAction { direction in
                            let distance: CGFloat = direction == .increment ? 8 : -8
                            let delta = CGSize(width: handle.direction.x * distance, height: handle.direction.y * distance)
                            session.update(displayRect: CropGeometry.resized(box, handle: handle, by: delta, in: frame, ratio: session.ratio.value), imageFrame: frame)
                        }
                        .position(x: point.x, y: point.y)
                }
            }
        }
        .frame(width: size.width, height: size.height).coordinateSpace(name: "cropCanvas").clipped()
    }

    private var cropValue: String {
        String(format: String(localized: "宽 %d%%，高 %d%%"), Int((session.rect.width * 100).rounded()), Int((session.rect.height * 100).rounded()))
    }

    private func cropGesture(frame: CGRect, handle: CropHandle?) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("cropCanvas"))
            .onChanged { value in
                if gestureStart == nil { gestureStart = session.rect }
                let original = CropSession(rect: gestureStart)
                let box = original.displayRect(in: frame)
                let next = handle.map { CropGeometry.resized(box, handle: $0, by: value.translation, in: frame, ratio: session.ratio.value) }
                    ?? CropGeometry.moved(box, by: value.translation, in: frame)
                session.update(displayRect: next, imageFrame: frame)
            }
            .onEnded { _ in gestureStart = nil }
    }
}

private struct CropMask: Shape {
    let imageFrame: CGRect
    let box: CGRect
    func path(in rect: CGRect) -> Path { var path = Path(); path.addRect(imageFrame); path.addRect(box); return path }
}

private struct CropGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [CGFloat(1 / 3.0), CGFloat(2 / 3.0)] {
            path.move(to: CGPoint(x: rect.width * fraction, y: 0)); path.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
            path.move(to: CGPoint(x: 0, y: rect.height * fraction)); path.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
        }
        return path
    }
}

private struct CropHandleMark: Shape {
    let handle: CropHandle
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let direction = handle.direction
        if handle.isCorner {
            let corner = handle.point(in: rect)
            path.move(to: CGPoint(x: corner.x, y: rect.midY))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: rect.midX, y: corner.y))
        } else if direction.x == 0 {
            path.move(to: CGPoint(x: 0, y: rect.midY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: 0)); path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        return path
    }
}

private extension CropHandle {
    var label: LocalizedStringKey {
        switch self {
        case .topLeft: "调整左上角"
        case .top: "调整上边缘"
        case .topRight: "调整右上角"
        case .right: "调整右边缘"
        case .bottomRight: "调整右下角"
        case .bottom: "调整下边缘"
        case .bottomLeft: "调整左下角"
        case .left: "调整左边缘"
        }
    }
}


private struct CropDoneStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(GlancePalette.accent, in: .rect(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
