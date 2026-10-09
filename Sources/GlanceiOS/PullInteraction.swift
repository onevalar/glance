//
//  PullInteraction.swift
//  Glance (iPhone / iPad)
//
//  Pulling a photo up or down. The photo is lifted out of the pager into a full-screen stage, follows the finger
//  (position, size and tilt) and is thrown: down into a wire-mesh trash bin, up into a star as a streak of light.
//  Everything here is UIKit and Core Animation so the drag never goes through SwiftUI.
//

import SwiftUI
import UIKit

/// What a finished pull did.
enum PullOutcome: Equatable {
    case discard
    case rate(Int)
}

/// Shared with SwiftUI so the bars can step aside while a photo is being pulled.
@MainActor
final class DragPhaseModel: ObservableObject {
    enum Phase { case idle, rating, trashing }
    /// Changes only when a pull starts, switches direction or ends.
    @Published var phase: Phase = .idle
}

// MARK: - Trash bin artwork

/// A classic wire-mesh office bin, drawn once. It is split in two images, the inside/back rim and the front wall,
/// so a photo can sit between them and visibly fall *into* the opening.
@MainActor
enum TrashBinArt {
    nonisolated static let size = CGSize(width: 108, height: 126)
    /// The opening (top rim) ellipse.
    nonisolated static let rim = CGRect(x: 3, y: 6, width: 102, height: 28)
    /// The floor ring.
    nonisolated static let base = CGRect(x: 19, y: 106, width: 70, height: 14)

    static let back: UIImage = render { context in
        let cg = context.cgContext
        // Contact shadow on the floor.
        cg.saveGState()
        cg.setShadow(offset: .zero, blur: 8, color: UIColor.black.withAlphaComponent(0.45).cgColor)
        cg.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
        cg.fillEllipse(in: base.insetBy(dx: -6, dy: 0).offsetBy(dx: 0, dy: 3))
        cg.restoreGState()

        // The inside: dark, a little lighter towards the front lip.
        cg.saveGState()
        UIBezierPath(ovalIn: rim).addClip()
        let inside = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                colors: [UIColor(white: 0.08, alpha: 1).cgColor, UIColor(white: 0.30, alpha: 1).cgColor] as CFArray,
                                locations: [0, 1])!
        cg.drawLinearGradient(inside, start: CGPoint(x: 0, y: rim.minY), end: CGPoint(x: 0, y: rim.maxY), options: [])
        // The back wall's mesh, seen through the opening.
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
        cg.setLineWidth(0.8)
        var x = rim.minX - rim.height
        while x < rim.maxX + rim.height {
            cg.move(to: CGPoint(x: x, y: rim.minY)); cg.addLine(to: CGPoint(x: x + rim.height, y: rim.maxY))
            cg.move(to: CGPoint(x: x + rim.height, y: rim.minY)); cg.addLine(to: CGPoint(x: x, y: rim.maxY))
            x += 8
        }
        cg.strokePath()
        cg.restoreGState()

        // Back half of the rim.
        let backRim = halfEllipse(rim, front: false)
        UIColor(white: 0.62, alpha: 1).setStroke()
        backRim.lineWidth = 3.4
        backRim.stroke()
    }

    static let front: UIImage = render { context in
        let cg = context.cgContext
        // Walls: rim (left) → floor (left) → front of the floor ring → floor (right) → rim (right) → front of the rim.
        let body = UIBezierPath()
        body.move(to: CGPoint(x: rim.minX, y: rim.midY))
        body.addLine(to: CGPoint(x: base.minX, y: base.midY))
        addArc(body, base, from: .pi, to: 0)
        body.addLine(to: CGPoint(x: rim.maxX, y: rim.midY))
        addArc(body, rim, from: 0, to: .pi)
        body.close()

        cg.saveGState()
        body.addClip()
        // Brushed metal, darker towards the sides so it reads as a cylinder.
        let metal = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            UIColor(white: 0.46, alpha: 0.96).cgColor,
            UIColor(white: 0.86, alpha: 0.93).cgColor,
            UIColor(white: 0.97, alpha: 0.92).cgColor,
            UIColor(white: 0.74, alpha: 0.93).cgColor,
            UIColor(white: 0.42, alpha: 0.96).cgColor,
        ] as CFArray, locations: [0, 0.22, 0.42, 0.72, 1])!
        cg.drawLinearGradient(metal, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: 0), options: [])
        // Wire mesh: dark wires with a fine highlight beside each, so the holes read as holes.
        let step: CGFloat = 9
        let reach = size.height
        func mesh(offset: CGFloat) -> CGPath {
            let path = CGMutablePath()
            var x = -reach
            while x < size.width + reach {
                path.move(to: CGPoint(x: x + offset, y: rim.midY)); path.addLine(to: CGPoint(x: x + offset + reach * 0.62, y: size.height))
                path.move(to: CGPoint(x: x + offset + reach * 0.62, y: rim.midY)); path.addLine(to: CGPoint(x: x + offset, y: size.height))
                x += step
            }
            return path
        }
        cg.addPath(mesh(offset: 0.9))
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
        cg.setLineWidth(0.7)
        cg.strokePath()
        cg.addPath(mesh(offset: 0))
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.34).cgColor)
        cg.setLineWidth(0.9)
        cg.strokePath()
        // A soft vertical sheen.
        let sheen = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [UIColor.white.withAlphaComponent(0).cgColor,
                                        UIColor.white.withAlphaComponent(0.28).cgColor,
                                        UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                               locations: [0, 0.5, 1])!
        cg.drawLinearGradient(sheen, start: CGPoint(x: size.width * 0.26, y: 0), end: CGPoint(x: size.width * 0.50, y: 0), options: [])
        cg.restoreGState()

        // Outline, floor ring and the thick rolled front rim.
        UIColor.black.withAlphaComponent(0.28).setStroke()
        body.lineWidth = 1
        body.stroke()

        let floorRing = halfEllipse(base, front: true)
        floorRing.lineWidth = 3.2
        UIColor(white: 0.55, alpha: 1).setStroke()
        floorRing.stroke()

        let frontRim = halfEllipse(rim, front: true)
        frontRim.lineCapStyle = .round
        frontRim.lineWidth = 4.6
        UIColor(white: 0.70, alpha: 1).setStroke()
        frontRim.stroke()
        frontRim.lineWidth = 1.6
        UIColor(white: 0.98, alpha: 1).setStroke()
        frontRim.apply(CGAffineTransform(translationX: 0, y: -0.9))
        frontRim.stroke()
    }

    /// Half of an ellipse: the front (lower) or back (upper) arc, drawn left to right.
    private static func halfEllipse(_ rect: CGRect, front: Bool) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        addArc(path, rect, from: .pi, to: front ? 0 : 2 * .pi)
        return path
    }

    /// Continues `path` along an ellipse (angles in screen coordinates: π/2 is the bottom).
    private static func addArc(_ path: UIBezierPath, _ rect: CGRect, from start: CGFloat, to end: CGFloat) {
        let steps = 40
        for step in 0...steps {
            let angle = start + (end - start) * CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(x: rect.midX + cos(angle) * rect.width / 2, y: rect.midY + sin(angle) * rect.height / 2))
        }
    }

    private static func render(_ draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        UIGraphicsImageRenderer(size: size).image(actions: draw)
    }
}

// MARK: - Star row

/// The stars, on a glass capsule at the top of the screen (where the top bar was).
final class StarRowView: UIView {
    static let sideInset: CGFloat = 18
    static let height: CGFloat = 74
    static let gold = UIColor(red: 1.0, green: 0.76, blue: 0.20, alpha: 1)

    private let background: UIVisualEffectView
    private var stars: [UIImageView] = []
    private(set) var lit = 0
    private(set) var target: Int?

    var count = 5 {
        didSet { if count != oldValue { rebuild() } }
    }

    override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            background = UIVisualEffectView(effect: UIGlassEffect())
        } else {
            background = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }
        super.init(frame: frame)
        isUserInteractionEnabled = false
        background.layer.cornerCurve = .continuous
        background.clipsToBounds = true
        addSubview(background)
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rebuild() {
        stars.forEach { $0.removeFromSuperview() }
        stars = (0..<count).map { _ in
            let view = UIImageView()
            view.contentMode = .center
            view.layer.shadowColor = UIColor.orange.cgColor
            view.layer.shadowOffset = .zero
            view.layer.shadowRadius = 8
            addSubview(view)
            return view
        }
        lit = -1
        show(lit: 0, target: nil, animated: false)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        background.layer.cornerRadius = bounds.height / 2
        for (index, star) in stars.enumerated() {
            star.bounds = CGRect(x: 0, y: 0, width: 56, height: 56)
            star.center = CGPoint(x: (CGFloat(index) + 0.5) * bounds.width / CGFloat(max(count, 1)), y: bounds.midY)
        }
    }

    /// Centre of star `n` (1…count) in `view`'s coordinates.
    func center(ofStar n: Int, in view: UIView) -> CGPoint {
        let x = (CGFloat(n - 1) + 0.5) * bounds.width / CGFloat(max(count, 1))
        return convert(CGPoint(x: x, y: bounds.midY), to: view)
    }

    /// The star whose column contains `x` (in `view`'s coordinates).
    func star(atX x: CGFloat, in view: UIView) -> Int {
        let local = convert(CGPoint(x: x, y: 0), from: view).x
        let index = Int(local / max(bounds.width, 1) * CGFloat(count))
        return min(max(index, 0), count - 1) + 1
    }

    private static func image(filled: Bool) -> UIImage? {
        let config = UIImage.SymbolConfiguration(pointSize: 31, weight: .semibold)
        return UIImage(systemName: filled ? "star.fill" : "star", withConfiguration: config)
    }

    /// Stars 1…`lit` are filled; `target` (the one the photo is heading for) is lifted a little.
    func show(lit newLit: Int, target newTarget: Int?, animated: Bool = true) {
        guard newLit != lit || newTarget != target else { return }
        lit = newLit
        target = newTarget
        let apply = {
            for (index, star) in self.stars.enumerated() {
                let n = index + 1
                let on = n <= newLit
                star.image = Self.image(filled: on)
                star.tintColor = on ? Self.gold : UIColor.label.withAlphaComponent(0.5)
                star.layer.shadowOpacity = on ? 0.55 : 0
                star.transform = n == newTarget ? CGAffineTransform(translationX: 0, y: -4).scaledBy(x: 1.28, y: 1.28)
                                                : (on ? CGAffineTransform(scaleX: 1.04, y: 1.04) : .identity)
            }
        }
        if animated {
            UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: apply)
        } else {
            apply()
        }
    }

    /// The light has arrived in star `n`: it flares, the stars before it fill in one after another.
    func celebrate(_ n: Int) {
        lit = n
        target = nil
        for (index, star) in stars.enumerated() {
            let number = index + 1
            let on = number <= n
            let delay = on ? Double(n - number) * 0.045 : 0
            UIView.animate(withDuration: 0.12, delay: delay, options: [.beginFromCurrentState]) {
                star.image = Self.image(filled: on)
                star.tintColor = on ? Self.gold : UIColor.label.withAlphaComponent(0.4)
                star.layer.shadowOpacity = on ? 0.7 : 0
                star.transform = number == n ? CGAffineTransform(scaleX: 1.55, y: 1.55) : (on ? CGAffineTransform(scaleX: 1.18, y: 1.18) : .identity)
            } completion: { _ in
                UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.42, initialSpringVelocity: 0,
                               options: [.beginFromCurrentState]) {
                    star.transform = .identity
                }
            }
        }
        guard stars.indices.contains(n - 1) else { return }
        burst(at: stars[n - 1].center)
    }

    /// A ring and a few sparks spreading from where the light landed.
    private func burst(at point: CGPoint) {
        var created: [CALayer] = []
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: CGRect(x: -16, y: -16, width: 32, height: 32)).cgPath
        ring.position = point
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = Self.gold.cgColor
        ring.lineWidth = 2.5
        ring.opacity = 0
        layer.addSublayer(ring)
        created.append(ring)

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.5
        grow.toValue = 2.3
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.95
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "burst")

        for index in 0..<7 {
            let angle = CGFloat(index) / 7 * 2 * .pi + 0.3
            let spark = CALayer()
            spark.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
            spark.cornerRadius = 2
            spark.backgroundColor = UIColor(red: 1, green: 0.92, blue: 0.6, alpha: 1).cgColor
            spark.position = point
            spark.opacity = 0
            layer.addSublayer(spark)
            created.append(spark)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = point
            move.toValue = CGPoint(x: point.x + cos(angle) * 34, y: point.y + sin(angle) * 34)
            let sparkFade = CABasicAnimation(keyPath: "opacity")
            sparkFade.fromValue = 1
            sparkFade.toValue = 0
            let sparkGroup = CAAnimationGroup()
            sparkGroup.animations = [move, sparkFade]
            sparkGroup.duration = 0.45
            sparkGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
            spark.add(sparkGroup, forKey: "spark")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            created.forEach { $0.removeFromSuperlayer() }
        }
    }
}

// MARK: - The lifted photo

/// A copy of the photo that leaves the page and follows the finger; it can glow until it is pure light.
final class PhotoFlyer: UIView {
    let imageView = UIImageView()
    private let glow = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerCurve = .continuous
        addSubview(imageView)

        glow.type = .radial
        glow.colors = [UIColor(white: 1, alpha: 1).cgColor,
                       UIColor(red: 1, green: 0.88, blue: 0.55, alpha: 0.95).cgColor,
                       UIColor(red: 1, green: 0.72, blue: 0.25, alpha: 0.75).cgColor]
        glow.locations = [0, 0.45, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.opacity = 0
        imageView.layer.addSublayer(glow)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 10)
        layer.shadowRadius = 24
        layer.shadowOpacity = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = imageView.bounds
        CATransaction.commit()
    }

    /// Corner radius as it appears on screen at the given scale.
    func setCorner(_ visible: CGFloat, scale: CGFloat) {
        imageView.layer.cornerRadius = visible / max(scale, 0.01)
    }

    /// 0 = the photo, 1 = a bright warm light.
    func setGlow(_ amount: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.opacity = Float(amount)
        CATransaction.commit()
        layer.shadowColor = amount > 0.01 ? UIColor(red: 1, green: 0.75, blue: 0.25, alpha: 1).cgColor : UIColor.black.cgColor
        layer.shadowOffset = amount > 0.01 ? .zero : CGSize(width: 0, height: 10)
        layer.shadowRadius = 24 - 8 * amount
    }

    func setLift(_ amount: CGFloat) {
        layer.shadowOpacity = Float(amount)
    }
}

// MARK: - Stage

/// Full-screen layer above the pager where a pulled photo lives until it lands (or goes back).
final class PullStageView: UIView {
    private enum Mode { case up, down }

    // Configuration from SwiftUI.
    var starCount = 5 { didSet { starRow.count = starCount } }
    /// Window y of the star row's centre (the top bar's centre), 0 = default.
    var starRowWindowY: CGFloat = 0 { didSet { setNeedsLayout() } }

    var onPhase: ((DragPhaseModel.Phase) -> Void)?
    var onCommit: ((PullOutcome) -> Void)?
    /// The stage is idle again; the pager may scroll.
    var onFinish: (() -> Void)?

    private(set) var isBusy = false
    private var isTracking = false

    private let binBack = UIImageView(image: TrashBinArt.back)
    private let binFront = UIImageView(image: TrashBinArt.front)
    private let binGlow = CAShapeLayer()
    private let flyerLayer = UIView()
    private let starRow = StarRowView()
    private var flyer: PhotoFlyer?

    private var mode: Mode?
    private var originFrame: CGRect = .zero
    private var touchStart: CGPoint = .zero
    /// From the photo's centre to the finger, at full size: keeps the touched spot under the finger as it shrinks.
    private var grip: CGPoint = .zero
    private var tilt: CGFloat = 0
    private var scale: CGFloat = 1
    private var binRise: CGFloat = 0
    private var binReady = false
    private var restoreSource: ((_ animated: Bool) -> Void)?

    private let selection = UISelectionFeedbackGenerator()
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let thud = UIImpactFeedbackGenerator(style: .medium)
    private let success = UINotificationFeedbackGenerator()

    private static let discardDistance: CGFloat = 150
    private static let starBand: CGFloat = 58

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        binGlow.path = UIBezierPath(ovalIn: TrashBinArt.rim.insetBy(dx: 6, dy: 3)).cgPath
        binGlow.fillColor = UIColor.systemRed.withAlphaComponent(0.38).cgColor
        binGlow.shadowColor = UIColor.systemRed.cgColor
        binGlow.shadowRadius = 10
        binGlow.shadowOpacity = 0.7
        binGlow.shadowOffset = .zero
        binGlow.opacity = 0
        binBack.layer.addSublayer(binGlow)

        // The photo sits between the inside of the bin and its front wall (so it can fall in), and above the stars.
        for view in [binBack, starRow, flyerLayer, binFront] as [UIView] { addSubview(view) }
        flyerLayer.isUserInteractionEnabled = false
        binBack.alpha = 0
        binFront.alpha = 0
        starRow.alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var safeInsets: UIEdgeInsets { window?.safeAreaInsets ?? safeAreaInsets }

    private var rowCenterY: CGFloat {
        if starRowWindowY > 0 { return convert(CGPoint(x: 0, y: starRowWindowY), from: nil).y }
        return safeInsets.top + 30
    }

    /// Where the bin stands when it has fully risen (its bottom just above the home indicator).
    private var binRestCenter: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.maxY - safeInsets.bottom - 8 - TrashBinArt.size.height / 2)
    }

    /// Centre of the opening of the bin at rest, in stage coordinates.
    private var binOpening: CGPoint {
        let rest = binRestCenter
        return CGPoint(x: rest.x, y: rest.y - TrashBinArt.size.height / 2 + TrashBinArt.rim.midY)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        flyerLayer.frame = bounds
        let width = bounds.width - StarRowView.sideInset * 2
        starRow.bounds = CGRect(x: 0, y: 0, width: width, height: StarRowView.height)
        starRow.center = CGPoint(x: bounds.midX, y: rowCenterY)
        if !isTracking && !isBusy { placeBin(rise: 0) }
    }

    // MARK: Bin

    private func placeBin(rise: CGFloat, extra: CGAffineTransform = .identity) {
        let rest = binRestCenter
        let travel = TrashBinArt.size.height + safeInsets.bottom + 40
        let eased = 1 - pow(1 - rise, 2)
        for view in [binBack, binFront] {
            view.bounds = CGRect(origin: .zero, size: TrashBinArt.size)
            view.center = CGPoint(x: rest.x, y: rest.y + (1 - eased) * travel)
            view.transform = extra
            view.alpha = min(1, rise * 3)
        }
    }

    private func setBinReady(_ ready: Bool) {
        guard ready != binReady else { return }
        binReady = ready
        if ready { lightImpact.impactOccurred() }
        let glow = CABasicAnimation(keyPath: "opacity")
        glow.fromValue = binGlow.presentation()?.opacity ?? binGlow.opacity
        glow.toValue = ready ? 1 : 0
        glow.duration = 0.2
        binGlow.opacity = ready ? 1 : 0
        binGlow.add(glow, forKey: "glow")
        // Anchored at the floor: it grows towards the photo a little, like it is ready to catch it.
        let lift = ready ? Self.bottomAnchored(sx: 1.1, sy: 1.1) : .identity
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.binBack.transform = lift
            self.binFront.transform = lift
        }
    }

    private static func bottomAnchored(sx: CGFloat, sy: CGFloat) -> CGAffineTransform {
        let h = TrashBinArt.size.height
        return CGAffineTransform(translationX: 0, y: h * (1 - sy) / 2).scaledBy(x: sx, y: sy)
    }

    // MARK: Tracking

    /// Lifts the photo out of the page. `frame` is where it is drawn now, `finger` where it was touched.
    func begin(image: UIImage, frame: CGRect, finger: CGPoint, restore: @escaping (_ animated: Bool) -> Void) {
        isTracking = true
        mode = nil
        originFrame = frame
        touchStart = finger
        grip = CGPoint(x: finger.x - frame.midX, y: finger.y - frame.midY)
        tilt = 0
        scale = 1
        binRise = 0
        binReady = false
        binGlow.opacity = 0
        restoreSource = restore

        let flyer = PhotoFlyer(frame: frame)
        flyer.imageView.image = image
        flyerLayer.addSubview(flyer)
        self.flyer = flyer
        starRow.count = starCount
        starRow.show(lit: 0, target: nil, animated: false)
        selection.prepare()
        lightImpact.prepare()
    }

    func move(finger: CGPoint, velocity: CGPoint) {
        guard isTracking, let flyer else { return }
        let dx = finger.x - touchStart.x
        let dy = finger.y - touchStart.y
        let newMode: Mode? = dy > 0 ? .down : (dy < 0 ? .up : mode)
        if newMode != mode {
            mode = newMode
            onPhase?(newMode == .down ? .trashing : .rating)
        }

        // The photo leans the way it is moved, like a card held at one corner.
        let wantedTilt = (dx / 900 + velocity.x / 7000).clamped(-0.2, 0.2)
        tilt += (wantedTilt - tilt) * 0.3

        let width = max(originFrame.width, 1)
        switch mode {
        case .down?:
            // Smaller the closer it gets to the opening, where it is just small enough to go in.
            let opening = binOpening
            let reach = max(opening.y - 40 - touchStart.y, 120)
            let progress = (dy / reach).clamped(0, 1)
            scale = 1 - (1 - dropScale(fraction: 0.8)) * (1 - pow(1 - progress, 2))
            flyer.setCorner(4 + 10 * progress, scale: scale)
            flyer.setGlow(0)
            flyer.setLift(0.35 * progress)
            binRise = (dy / 120).clamped(0, 1)
            UIView.performWithoutAnimation { placeBin(rise: binRise, extra: binBack.transform) }
            setBinReady(dy >= Self.discardDistance)
            starRow.alpha = 0
        case .up?:
            let span = max(touchStart.y - rowCenterY, 160)
            let progress = (-dy / span).clamped(0, 1)
            // It shrinks, rounds off and brightens until it is a small ball of light at the stars.
            let longest = max(originFrame.width, originFrame.height, 1)
            let endScale = (46 / longest).clamped(0.04, 0.5)
            scale = 1 - (1 - endScale) * (1 - pow(1 - progress, 1.6))
            let shortSide = min(originFrame.width, originFrame.height) * scale
            flyer.setCorner(4 + max(0, shortSide / 2 - 4) * progress * progress, scale: scale)
            let light = ((progress - 0.25) / 0.7).clamped(0, 1)
            flyer.setGlow(light)
            flyer.setLift(0.3 + 0.6 * light)
            binRise = 0
            if binBack.alpha > 0 { setBinReady(false); UIView.performWithoutAnimation { placeBin(rise: 0) } }
            // The row fades in once the pull is clearly meant (a small drift shows only a hint of it).
            let reveal = ((-dy - 14) / 70).clamped(0, 1)
            starRow.alpha = reveal
            starRow.transform = CGAffineTransform(translationX: 0, y: -12 * (1 - reveal))
            let aimed = aimedStar(finger: finger, velocity: velocity, progress: progress)
            if aimed != starRow.target {
                if aimed != nil { selection.selectionChanged() }
                starRow.show(lit: aimed ?? 0, target: aimed)
            }
        case nil:
            break
        }

        var center = CGPoint(x: finger.x - grip.x * scale, y: finger.y - grip.y * scale)
        if mode == .down, binRise > 0.5 {
            // The bin is solid: the photo can rest on the opening but not be pushed through it,
            // and near it it is drawn gently towards the middle.
            let opening = binOpening
            let near = ((center.y - (opening.y - 260)) / 260).clamped(0, 1)
            center.x += (opening.x - center.x) * 0.35 * near * near
            let lowest = opening.y + 6 - originFrame.height * scale / 2
            if center.y > lowest { center.y = lowest + (center.y - lowest) * 0.12 }
        }
        flyer.center = center
        flyer.transform = CGAffineTransform(rotationAngle: tilt).scaledBy(x: scale, y: scale)
    }

    /// Scale at which the photo fits `fraction` of the bin's opening (tall photos are limited by their height).
    private func dropScale(fraction: CGFloat) -> CGFloat {
        let byWidth = TrashBinArt.rim.width * fraction / max(originFrame.width, 1)
        let byHeight = TrashBinArt.rim.width * fraction * 1.3 / max(originFrame.height, 1)
        return min(byWidth, byHeight).clamped(0.04, 0.6)
    }

    /// The star the photo would land in: the one under the finger, or (while flicking up) the one on its path.
    private func aimedStar(finger: CGPoint, velocity: CGPoint, progress: CGFloat, releasing: Bool = false) -> Int? {
        if abs(finger.y - rowCenterY) <= Self.starBand { return starRow.star(atX: finger.x, in: self) }
        let fastEnough = releasing ? velocity.y < -650 : velocity.y < -900
        guard progress > 0.25, fastEnough, finger.y > rowCenterY else { return nil }
        let time = (rowCenterY - finger.y) / velocity.y
        let x = finger.x + velocity.x * time
        return starRow.star(atX: x, in: self)
    }

    func end(finger: CGPoint, velocity: CGPoint, cancelled: Bool) {
        guard isTracking else { return }
        isTracking = false
        isBusy = true
        let dy = finger.y - touchStart.y
        switch mode {
        case .down? where !cancelled && (dy >= Self.discardDistance || (velocity.y > 900 && dy > 60)):
            dropIntoBin(velocity: velocity)
        case .up? where !cancelled:
            let span = max(touchStart.y - rowCenterY, 160)
            let progress = (-dy / span).clamped(0, 1)
            if let star = aimedStar(finger: finger, velocity: velocity, progress: progress, releasing: true) {
                flyIntoStar(star, velocity: velocity)
            } else {
                putBack(velocity: velocity)
            }
        default:
            putBack(velocity: velocity)
        }
    }

    // MARK: Endings

    /// Spring timing whose start speed matches the finger (relative to the remaining distance).
    private static func spring(damping: CGFloat, velocity: CGPoint, from: CGPoint, to: CGPoint) -> UISpringTimingParameters {
        let distance = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let relX = abs(distance.x) > 1 ? (velocity.x / distance.x).clamped(-25, 25) : 0
        let relY = abs(distance.y) > 1 ? (velocity.y / distance.y).clamped(-25, 25) : 0
        return UISpringTimingParameters(dampingRatio: damping, initialVelocity: CGVector(dx: relX, dy: relY))
    }

    /// Not far enough: the photo springs back into its page.
    private func putBack(velocity: CGPoint) {
        guard let flyer else { finish(); return }
        let target = CGPoint(x: originFrame.midX, y: originFrame.midY)
        let move = UIViewPropertyAnimator(duration: 0.5,
                                          timingParameters: Self.spring(damping: 0.8, velocity: velocity, from: flyer.center, to: target))
        move.addAnimations { flyer.center = target }
        let shape = UIViewPropertyAnimator(duration: 0.42, dampingRatio: 0.86) {
            flyer.transform = .identity
            flyer.setCorner(0, scale: 1)
            flyer.setLift(0)
            self.starRow.alpha = 0
            self.placeBin(rise: 0)
        }
        flyer.setGlow(0)
        setBinReady(false)
        move.addCompletion { _ in
            self.restoreSource?(false)
            self.finish()
        }
        move.startAnimation()
        shape.startAnimation()
    }

    /// Thrown down: it flies to the opening, drops in behind the front wall, the bin catches it.
    private func dropIntoBin(velocity: CGPoint) {
        guard let flyer else { finish(); return }
        setBinReady(true)
        let opening = binOpening
        let hover = CGPoint(x: opening.x, y: opening.y - 10)
        let endScale = dropScale(fraction: 0.6)
        let lean: CGFloat = (tilt >= 0 ? 1 : -1) * 0.12

        let toOpening = UIViewPropertyAnimator(duration: 0.34,
                                               timingParameters: Self.spring(damping: 0.92, velocity: velocity, from: flyer.center, to: hover))
        toOpening.addAnimations { flyer.center = hover }
        let shrink = UIViewPropertyAnimator(duration: 0.3, curve: .easeOut) {
            flyer.transform = CGAffineTransform(rotationAngle: lean).scaledBy(x: endScale, y: endScale)
            flyer.setCorner(6, scale: endScale)
            self.placeBin(rise: 1, extra: Self.bottomAnchored(sx: 1.1, sy: 1.1))
        }
        toOpening.addCompletion { _ in
            // Falls in: the front wall of the bin covers it as it goes down.
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
                flyer.center.y += 52
                flyer.transform = CGAffineTransform(rotationAngle: lean * 1.6).scaledBy(x: endScale * 0.82, y: endScale * 0.82)
            } completion: { _ in
                flyer.alpha = 0
                self.catchInBin()
            }
        }
        toOpening.startAnimation()
        shrink.startAnimation()
    }

    private func catchInBin() {
        thud.impactOccurred()
        setBinReady(false)
        // The bin gives a little under the weight, then settles.
        UIView.animate(withDuration: 0.09, delay: 0, options: [.curveEaseOut]) {
            let squash = Self.bottomAnchored(sx: 1.08, sy: 0.9)
            self.binBack.transform = squash
            self.binFront.transform = squash
        } completion: { _ in
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.4, initialSpringVelocity: 0, options: []) {
                self.binBack.transform = .identity
                self.binFront.transform = .identity
            }
        }
        onCommit?(.discard)
        // Then it sinks away; the next photo has slid in meanwhile.
        UIView.animate(withDuration: 0.32, delay: 0.42, options: [.curveEaseIn]) {
            self.placeBin(rise: 0)
        } completion: { _ in
            self.restoreSource?(true)
            self.finish()
        }
    }

    /// Thrown up: the photo collapses into light that streaks along its path into the star.
    private func flyIntoStar(_ star: Int, velocity: CGPoint) {
        guard let flyer else { finish(); return }
        let start = flyer.center
        let end = starRow.center(ofStar: star, in: self)
        starRow.show(lit: star, target: star)

        // 1. The photo burns into light where it is.
        flyer.setGlow(1)
        UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut]) {
            flyer.transform = flyer.transform.scaledBy(x: 0.3, y: 0.3)
            flyer.alpha = 0
        }

        // 2. The light continues the throw and bends into the star.
        let speed = hypot(velocity.x, velocity.y)
        let reach = min(speed * 0.09, 150)
        let direction = speed > 1 ? CGPoint(x: velocity.x / speed, y: velocity.y / speed) : CGPoint(x: 0, y: -1)
        let control = CGPoint(x: start.x + direction.x * reach, y: start.y + direction.y * reach)
        let path = UIBezierPath()
        path.move(to: start)
        path.addQuadCurve(to: end, controlPoint: control)
        let distance = hypot(end.x - start.x, end.y - start.y)
        let duration = Double((distance / 1500).clamped(0.2, 0.36))

        let beam = Self.makeBeam()
        beam.position = end
        layer.addSublayer(beam)

        let travel = CAKeyframeAnimation(keyPath: "position")
        travel.path = path.cgPath
        travel.rotationMode = .rotateAuto
        travel.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.9, 0.6)
        let stretch = CAKeyframeAnimation(keyPath: "bounds.size.width")
        stretch.values = [24, 96, 40]
        stretch.keyTimes = [0, 0.55, 1]
        let appear = CAKeyframeAnimation(keyPath: "opacity")
        appear.values = [0, 1, 1]
        appear.keyTimes = [0, 0.15, 1]
        let group = CAAnimationGroup()
        group.animations = [travel, stretch, appear]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            beam.removeFromSuperlayer()
            self.success.notificationOccurred(.success)
            self.starRow.celebrate(star)
            self.onCommit?(.rate(star))
            UIView.animate(withDuration: 0.28, delay: 0.55, options: [.curveEaseIn]) {
                self.starRow.alpha = 0
                self.starRow.transform = CGAffineTransform(translationX: 0, y: -10)
            } completion: { _ in
                self.restoreSource?(true)
                self.finish()
            }
        }
        beam.add(group, forKey: "flight")
        CATransaction.commit()
    }

    private static func makeBeam() -> CAGradientLayer {
        let beam = CAGradientLayer()
        beam.bounds = CGRect(x: 0, y: 0, width: 60, height: 12)
        beam.cornerRadius = 6
        beam.startPoint = CGPoint(x: 0, y: 0.5)
        beam.endPoint = CGPoint(x: 1, y: 0.5)
        beam.colors = [UIColor(red: 1, green: 0.7, blue: 0.2, alpha: 0).cgColor,
                       UIColor(red: 1, green: 0.78, blue: 0.3, alpha: 0.85).cgColor,
                       UIColor(red: 1, green: 0.97, blue: 0.85, alpha: 1).cgColor]
        beam.locations = [0, 0.6, 1]
        beam.shadowColor = UIColor(red: 1, green: 0.75, blue: 0.25, alpha: 1).cgColor
        beam.shadowRadius = 10
        beam.shadowOpacity = 1
        beam.shadowOffset = .zero
        beam.opacity = 0
        return beam
    }

    private func finish() {
        flyer?.removeFromSuperview()
        flyer = nil
        restoreSource = nil
        mode = nil
        isBusy = false
        starRow.alpha = 0
        starRow.transform = .identity
        placeBin(rise: 0)
        onPhase?(.idle)
        onFinish?()
    }
}

extension CGFloat {
    fileprivate func clamped(_ low: CGFloat, _ high: CGFloat) -> CGFloat { Swift.min(Swift.max(self, low), high) }
}
