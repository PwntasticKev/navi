import CoreGraphics
import Foundation

struct MagnifierStyle: Equatable, Sendable {
    let size: CGFloat
    let pixelCount: Int

    static let standard = MagnifierStyle(size: 76, pixelCount: 9)
    static let sizeRange: ClosedRange<CGFloat> = 64...200
    static let pixelRange: ClosedRange<Int> = 5...31
    static let pointsPerZoomStep: CGFloat = 24

    init(size: CGFloat, pixelCount: Int) {
        self.size = min(max(size.rounded(), Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        let clamped = min(max(pixelCount, Self.pixelRange.lowerBound), Self.pixelRange.upperBound)
        self.pixelCount = clamped.isMultiple(of: 2) ? clamped + 1 : clamped
    }

    func clampedDrag(_ drag: CGVector) -> CGVector {
        let fewestSteps = CGFloat(pixelCount - Self.pixelRange.upperBound) / 2
        let mostSteps = CGFloat(pixelCount - Self.pixelRange.lowerBound) / 2
        return CGVector(
            dx: min(max(drag.dx, fewestSteps * Self.pointsPerZoomStep), mostSteps * Self.pointsPerZoomStep),
            dy: min(max(drag.dy, Self.sizeRange.lowerBound - size), Self.sizeRange.upperBound - size)
        )
    }

    func resized(by drag: CGVector) -> MagnifierStyle {
        let steps = Int((drag.dx / Self.pointsPerZoomStep).rounded())
        return MagnifierStyle(size: size + drag.dy, pixelCount: pixelCount - steps * 2)
    }

    private enum Keys {
        static let size = "capture.magnifierSize"
        static let pixelCount = "capture.magnifierPixels"
    }

    static func load(from defaults: UserDefaults = .standard) -> MagnifierStyle {
        let size = defaults.double(forKey: Keys.size)
        let pixels = defaults.integer(forKey: Keys.pixelCount)
        guard size > 0, pixels > 0 else { return .standard }
        return MagnifierStyle(size: size, pixelCount: pixels)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(Double(size), forKey: Keys.size)
        defaults.set(pixelCount, forKey: Keys.pixelCount)
    }
}

enum MagnifierPlacement {
    static let gap: CGFloat = 20
    static let margin: CGFloat = 4
    static let glideDuration: Double = 0.12

    static func side(for point: CGPoint, panel: CGSize, in bounds: CGRect) -> CGVector {
        let right = point.x + gap + panel.width <= bounds.maxX - margin
        let below = point.y - gap - panel.height >= bounds.minY + margin
        return CGVector(dx: right ? 1 : -1, dy: below ? -1 : 1)
    }

    static func frame(for point: CGPoint, panel: CGSize, side: CGVector) -> CGRect {
        let center = CGPoint(
            x: point.x + side.dx * (gap + panel.width / 2),
            y: point.y + side.dy * (gap + panel.height / 2)
        )
        return CGRect(x: center.x - panel.width / 2, y: center.y - panel.height / 2, width: panel.width, height: panel.height)
    }

    static func pixelDrawRect(source: CGRect, cropSize: CGSize, cell: CGFloat, in body: CGRect) -> CGRect {
        let dx = max(0, -source.minX) * cell
        let dy = max(0, -source.minY) * cell
        return CGRect(
            x: body.minX + dx,
            y: body.maxY - dy - cropSize.height * cell,
            width: cropSize.width * cell,
            height: cropSize.height * cell
        )
    }

    static func glide(from start: CGVector, to end: CGVector, progress: Double) -> CGVector {
        let t = min(max(progress, 0), 1)
        let eased = CGFloat(1 - pow(1 - t, 3))
        return CGVector(dx: start.dx + (end.dx - start.dx) * eased, dy: start.dy + (end.dy - start.dy) * eased)
    }
}

struct MagnifierGlide {
    private var lastSide: CGVector?
    private var active: (from: CGVector, to: CGVector, start: CFTimeInterval)?

    var isGliding: Bool { active != nil }

    func isFinished(at time: CFTimeInterval) -> Bool {
        guard let active else { return true }
        return time - active.start >= MagnifierPlacement.glideDuration
    }

    mutating func side(toward target: CGVector, at time: CFTimeInterval, animates: Bool) -> CGVector {
        defer { lastSide = target }
        if let glide = active {
            let progress = (time - glide.start) / MagnifierPlacement.glideDuration
            let current = MagnifierPlacement.glide(from: glide.from, to: glide.to, progress: progress)
            if glide.to != target {
                active = animates ? (current, target, time) : nil
                return animates ? current : target
            }
            if progress < 1 { return current }
            active = nil
            return target
        }
        if animates, let lastSide, lastSide != target {
            active = (lastSide, target, time)
            return lastSide
        }
        return target
    }

    mutating func reset() {
        lastSide = nil
        active = nil
    }
}

struct MagnifierFooterLayout: Equatable {
    static let inset: CGFloat = 6
    static let swatchSize: CGFloat = 10
    static let spacing: CGFloat = 6
    static let coordinatesGap: CGFloat = 10

    let showsSwatch: Bool
    let showsCoordinates: Bool

    init(width: CGFloat, hexWidth: CGFloat, coordinatesWidth: CGFloat) {
        let swatchSpan = Self.swatchSize + Self.spacing
        showsSwatch = Self.inset * 2 + swatchSpan + hexWidth <= width
        let used = Self.inset * 2 + (showsSwatch ? swatchSpan : 0) + hexWidth
        showsCoordinates = used + Self.coordinatesGap + coordinatesWidth <= width
    }
}

struct PixelColor: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)

    static func read(from image: CGImage, x: Int, y: Int) -> PixelColor? {
        guard x >= 0, y >= 0, x < image.width, y < image.height,
              let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = sRGB
        else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return PixelColor(red: bytes[0], green: bytes[1], blue: bytes[2])
    }
}
