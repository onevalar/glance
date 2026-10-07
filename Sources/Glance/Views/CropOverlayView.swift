//
//  CropOverlayView.swift
//  Glance
//

import SwiftUI

enum CropRatio: String, CaseIterable, Identifiable {
    case free = "自由"
    case square = "1:1"
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case twoThree = "2:3"
    
    var id: String { self.rawValue }
    
    var value: CGFloat? {
        switch self {
        case .free: return nil
        case .square: return 1.0
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .twoThree: return 2.0 / 3.0
        }
    }
}

struct CropOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let imageSize: CGSize
    let viewSize: CGSize
    @Binding var cropRect: CGRect? // Normalized rect (0...1)
    
    let onCommit: (CGRect) -> Void
    let onCancel: () -> Void
    
    @State private var cropBoxFrame: CGRect = .zero
    @State private var selectedRatio: CropRatio = .free
    @State private var isDragging: Bool = false
    
    // Compute the standard fitted image frame in view bounds
    private var imageFrame: CGRect {
        let hRatio = viewSize.width / imageSize.width
        let vRatio = viewSize.height / imageSize.height
        let scale = min(hRatio, vRatio)
        
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        let x = (viewSize.width - w) / 2
        let y = (viewSize.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    var body: some View {
        ZStack {
            // 1. Dim Outer Overlay (EO Fill)
            DimOverlayShape(imageFrame: imageFrame, cropBox: cropBoxFrame)
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            
            // 2. Crop Box Border & Rule of Thirds
            ZStack {
                // Outer Border of the Crop Box
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                
                // Rule of Thirds Lines (only visible during drag)
                if isDragging {
                    GeometryReader { boxGeo in
                        let w = boxGeo.size.width
                        let h = boxGeo.size.height
                        
                        // Vertical lines
                        Path { p in
                            p.move(to: CGPoint(x: w / 3, y: 0))
                            p.addLine(to: CGPoint(x: w / 3, y: h))
                            p.move(to: CGPoint(x: 2 * w / 3, y: 0))
                            p.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                        }
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        
                        // Horizontal lines
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: h / 3))
                            p.addLine(to: CGPoint(x: w, y: h / 3))
                            p.move(to: CGPoint(x: 0, y: 2 * h / 3))
                            p.addLine(to: CGPoint(x: w, y: 2 * h / 3))
                        }
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    }
                }
            }
            .frame(width: cropBoxFrame.width, height: cropBoxFrame.height)
            .position(x: cropBoxFrame.midX, y: cropBoxFrame.midY)
            .allowsHitTesting(false)
            
            // 3. Drag Handles
            ZStack {
                // Corners
                CornerHandle(position: .topLeft, boxFrame: $cropBoxFrame, imageFrame: imageFrame, ratio: selectedRatio.value, isDragging: $isDragging)
                CornerHandle(position: .topRight, boxFrame: $cropBoxFrame, imageFrame: imageFrame, ratio: selectedRatio.value, isDragging: $isDragging)
                CornerHandle(position: .bottomLeft, boxFrame: $cropBoxFrame, imageFrame: imageFrame, ratio: selectedRatio.value, isDragging: $isDragging)
                CornerHandle(position: .bottomRight, boxFrame: $cropBoxFrame, imageFrame: imageFrame, ratio: selectedRatio.value, isDragging: $isDragging)
                
                // Edges (only active for free ratios)
                if selectedRatio == .free {
                    EdgeHandle(position: .top, boxFrame: $cropBoxFrame, imageFrame: imageFrame, isDragging: $isDragging)
                    EdgeHandle(position: .bottom, boxFrame: $cropBoxFrame, imageFrame: imageFrame, isDragging: $isDragging)
                    EdgeHandle(position: .left, boxFrame: $cropBoxFrame, imageFrame: imageFrame, isDragging: $isDragging)
                    EdgeHandle(position: .right, boxFrame: $cropBoxFrame, imageFrame: imageFrame, isDragging: $isDragging)
                }
            }
            .allowsHitTesting(true)
            
            // 4. Floating Control Bar (Top)
            VStack {
                HStack(spacing: 16) {
                    Button(action: onCancel) {
                        Text("取消")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding([.leading, .trailing], 12)
                            .padding([.top, .bottom], 6)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    
                    Button(action: resetCrop) {
                        Text("重置")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding([.leading, .trailing], 12)
                            .padding([.top, .bottom], 6)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    
                    // Ratio Selector
                    Picker("", selection: $selectedRatio) {
                        ForEach(CropRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .onChange(of: selectedRatio) { _, newRatio in
                        applyAspectRatio(newRatio)
                    }
                    
                    Spacer()
                    
                    Button(action: commitCrop) {
                        Text("应用")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                            .padding([.leading, .trailing], 16)
                            .padding([.top, .bottom], 6)
                            .background(Color.yellow)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .shadow(radius: 5)
                .padding(.top, 40)
                .padding([.leading, .trailing], 24)
                
                Spacer()
            }
        }
        .onAppear {
            initializeCropBox()
        }
        .onChange(of: viewSize) { _, _ in
            initializeCropBox()
        }
    }
    
    private func initializeCropBox() {
        let currentNormalized = cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        
        let x = imageFrame.minX + currentNormalized.origin.x * imageFrame.width
        let y = imageFrame.minY + currentNormalized.origin.y * imageFrame.height
        let w = currentNormalized.width * imageFrame.width
        let h = currentNormalized.height * imageFrame.height
        
        self.cropBoxFrame = CGRect(x: x, y: y, width: w, height: h)
        self.selectedRatio = .free
    }
    
    private func resetCrop() {
        self.cropBoxFrame = imageFrame
        self.selectedRatio = .free
    }
    
    private func commitCrop() {
        let normX = (cropBoxFrame.minX - imageFrame.minX) / imageFrame.width
        let normY = (cropBoxFrame.minY - imageFrame.minY) / imageFrame.height
        let normW = cropBoxFrame.width / imageFrame.width
        let normH = cropBoxFrame.height / imageFrame.height
        
        let normRect = CGRect(x: normX, y: normY, width: normW, height: normH)
        onCommit(normRect)
    }
    
    private func applyAspectRatio(_ ratio: CropRatio) {
        guard let ratioVal = ratio.value else { return }
        
        let cx = cropBoxFrame.midX
        let cy = cropBoxFrame.midY
        
        var newW = cropBoxFrame.width
        var newH = newW / ratioVal
        
        if newH > imageFrame.height {
            newH = imageFrame.height
            newW = newH * ratioVal
        }
        if newW > imageFrame.width {
            newW = imageFrame.width
            newH = newW / ratioVal
        }
        
        let newX = cx - newW / 2
        let newY = cy - newH / 2
        
        cropBoxFrame = clampBox(CGRect(x: newX, y: newY, width: newW, height: newH), in: imageFrame)
    }
}

// Even-Odd Overlay Shape
struct DimOverlayShape: Shape {
    let imageFrame: CGRect
    let cropBox: CGRect
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(imageFrame)
        path.addRect(cropBox)
        return path
    }
}

// Handles Placement & Drag Logic
enum HandleCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

struct CornerHandle: View {
    let position: HandleCorner
    @Binding var boxFrame: CGRect
    let imageFrame: CGRect
    let ratio: CGFloat?
    @Binding var isDragging: Bool
    
    private var positionPoint: CGPoint {
        switch position {
        case .topLeft: return CGPoint(x: boxFrame.minX, y: boxFrame.minY)
        case .topRight: return CGPoint(x: boxFrame.maxX, y: boxFrame.minY)
        case .bottomLeft: return CGPoint(x: boxFrame.minX, y: boxFrame.maxY)
        case .bottomRight: return CGPoint(x: boxFrame.maxX, y: boxFrame.maxY)
        }
    }
    
    var body: some View {
        ZStack {
            // Corner visual mark
            CornerMarkShape(corner: position)
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.5), radius: 1)
        }
        .frame(width: 32, height: 32) // Larger touch target
        .background(Color.white.opacity(0.01))
        .position(x: positionPoint.x, y: positionPoint.y)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    isDragging = true
                    handleDrag(val.location)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
    
    private func handleDrag(_ location: CGPoint) {
        var newBox = boxFrame
        let minSize: CGFloat = 40
        
        let loc = CGPoint(
            x: max(imageFrame.minX, min(imageFrame.maxX, location.x)),
            y: max(imageFrame.minY, min(imageFrame.maxY, location.y))
        )
        
        switch position {
        case .topLeft:
            let w = boxFrame.maxX - loc.x
            let h = boxFrame.maxY - loc.y
            if w >= minSize && h >= minSize {
                if let ratio = ratio {
                    // Lock ratio
                    let adjustedH = w / ratio
                    if boxFrame.maxY - adjustedH >= imageFrame.minY {
                        newBox = CGRect(x: loc.x, y: boxFrame.maxY - adjustedH, width: w, height: adjustedH)
                    }
                } else {
                    newBox = CGRect(x: loc.x, y: loc.y, width: w, height: h)
                }
            }
        case .topRight:
            let w = loc.x - boxFrame.minX
            let h = boxFrame.maxY - loc.y
            if w >= minSize && h >= minSize {
                if let ratio = ratio {
                    let adjustedH = w / ratio
                    if boxFrame.maxY - adjustedH >= imageFrame.minY {
                        newBox = CGRect(x: boxFrame.minX, y: boxFrame.maxY - adjustedH, width: w, height: adjustedH)
                    }
                } else {
                    newBox = CGRect(x: boxFrame.minX, y: loc.y, width: w, height: h)
                }
            }
        case .bottomLeft:
            let w = boxFrame.maxX - loc.x
            let h = loc.y - boxFrame.minY
            if w >= minSize && h >= minSize {
                if let ratio = ratio {
                    let adjustedH = w / ratio
                    if boxFrame.minY + adjustedH <= imageFrame.maxY {
                        newBox = CGRect(x: loc.x, y: boxFrame.minY, width: w, height: adjustedH)
                    }
                } else {
                    newBox = CGRect(x: loc.x, y: boxFrame.minY, width: w, height: h)
                }
            }
        case .bottomRight:
            let w = loc.x - boxFrame.minX
            let h = loc.y - boxFrame.minY
            if w >= minSize && h >= minSize {
                if let ratio = ratio {
                    let adjustedH = w / ratio
                    if boxFrame.minY + adjustedH <= imageFrame.maxY {
                        newBox = CGRect(x: boxFrame.minX, y: boxFrame.minY, width: w, height: adjustedH)
                    }
                } else {
                    newBox = CGRect(x: boxFrame.minX, y: boxFrame.minY, width: w, height: h)
                }
            }
        }
        
        boxFrame = clampBox(newBox, in: imageFrame)
    }
}

struct CornerMarkShape: Shape {
    let corner: HandleCorner
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        switch corner {
        case .topLeft:
            path.move(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
        case .topRight:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: h))
        case .bottomLeft:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: w, y: h))
        case .bottomRight:
            path.move(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w, y: 0))
        }
        return path
    }
}

enum HandleEdge {
    case top, bottom, left, right
}

struct EdgeHandle: View {
    let position: HandleEdge
    @Binding var boxFrame: CGRect
    let imageFrame: CGRect
    @Binding var isDragging: Bool
    
    private var centerPoint: CGPoint {
        switch position {
        case .top: return CGPoint(x: boxFrame.midX, y: boxFrame.minY)
        case .bottom: return CGPoint(x: boxFrame.midX, y: boxFrame.maxY)
        case .left: return CGPoint(x: boxFrame.minX, y: boxFrame.midY)
        case .right: return CGPoint(x: boxFrame.maxX, y: boxFrame.midY)
        }
    }
    
    var body: some View {
        ZStack {
            // Edge line marker
            Capsule()
                .fill(Color.white)
                .frame(
                    width: (position == .top || position == .bottom) ? 24 : 4,
                    height: (position == .top || position == .bottom) ? 4 : 24
                )
                .shadow(color: .black.opacity(0.5), radius: 1)
        }
        .frame(
            width: (position == .top || position == .bottom) ? 48 : 32,
            height: (position == .top || position == .bottom) ? 32 : 48
        )
        .background(Color.white.opacity(0.01))
        .position(x: centerPoint.x, y: centerPoint.y)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    isDragging = true
                    handleDrag(val.location)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
    
    private func handleDrag(_ location: CGPoint) {
        var newBox = boxFrame
        let minSize: CGFloat = 40
        
        let loc = CGPoint(
            x: max(imageFrame.minX, min(imageFrame.maxX, location.x)),
            y: max(imageFrame.minY, min(imageFrame.maxY, location.y))
        )
        
        switch position {
        case .top:
            let h = boxFrame.maxY - loc.y
            if h >= minSize {
                newBox.origin.y = loc.y
                newBox.size.height = h
            }
        case .bottom:
            let h = loc.y - boxFrame.minY
            if h >= minSize {
                newBox.size.height = h
            }
        case .left:
            let w = boxFrame.maxX - loc.x
            if w >= minSize {
                newBox.origin.x = loc.x
                newBox.size.width = w
            }
        case .right:
            let w = loc.x - boxFrame.minX
            if w >= minSize {
                newBox.size.width = w
            }
        }
        
        boxFrame = clampBox(newBox, in: imageFrame)
    }
}

// Helpers
func clampBox(_ box: CGRect, in bounds: CGRect) -> CGRect {
    let minX = max(bounds.minX, min(bounds.maxX, box.minX))
    let minY = max(bounds.minY, min(bounds.maxY, box.minY))
    let maxX = max(bounds.minX, min(bounds.maxX, box.maxX))
    let maxY = max(bounds.minY, min(bounds.maxY, box.maxY))
    
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}
