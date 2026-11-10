import CoreGraphics

/// Edit after capture: where the canvas sits on the frozen screen, and which screen pixels its base
/// image shows. Points are top-left display-local; pixels are top-left in the frozen screen image.
struct ScreenPlacement: Equatable, Sendable {
    /// The canvas's top-left corner on the screen, in points.
    let origin: CGPoint
    /// The screen pixels the base shows. Nil once rotate, flip, or resize means the base is no
    /// longer a plain piece of the screen. Then the frame can not be moved or resized.
    let source: CGRect?
    /// Pixels per point.
    let scale: CGFloat

    var canReframe: Bool { source != nil }

    /// The canvas on the screen, in points.
    func frame(pointSize: CGSize) -> CGRect {
        CGRect(origin: origin, size: pointSize)
    }

    /// The placement after an image edit. A crop moves the frame so the kept pixels stay where
    /// they are on screen. Any other edit locks the frame where it is.
    func after(_ edit: ImageEdit) -> ScreenPlacement {
        guard case let .crop(rect) = edit else {
            return ScreenPlacement(origin: origin, source: nil, scale: scale)
        }
        return ScreenPlacement(
            origin: CGPoint(x: origin.x + rect.minX / scale, y: origin.y + rect.minY / scale),
            source: source.map { CGRect(origin: CGPoint(x: $0.minX + rect.minX, y: $0.minY + rect.minY), size: rect.size) },
            scale: scale
        )
    }

    /// The placement for a new frame in points, kept inside a screen image of `screenPixels`, and
    /// how far marks move (in pixels) to stay on the same screen pixels. Nil when the frame is locked
    /// or the new frame misses the screen.
    func reframed(to frame: CGRect, screenPixels: CGSize) -> (placement: ScreenPlacement, shift: CGVector)? {
        guard let source else { return nil }
        let pixels = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            .integral
            .intersection(CGRect(origin: .zero, size: screenPixels))
        guard !pixels.isNull, pixels.width >= 1, pixels.height >= 1 else { return nil }
        let placement = ScreenPlacement(
            origin: CGPoint(x: pixels.minX / scale, y: pixels.minY / scale), source: pixels, scale: scale
        )
        return (placement, CGVector(dx: source.minX - pixels.minX, dy: source.minY - pixels.minY))
    }
}
