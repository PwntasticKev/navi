import CoreGraphics
import Foundation

/// Pure math for capture: coordinate spaces, crops, snapping, and file names.
///
/// Coordinate spaces:
/// - Cocoa global: origin at the bottom left of the primary display, y goes up (`NSScreen.frame`).
/// - Quartz global: origin at the top left of the primary display, y goes down (`CGWindowList`, `SCWindow.frame`).
/// - View local: origin at the bottom left of one display, in points.
/// - Image pixels: origin at the top left of a captured image, in pixels.
public enum CaptureGeometry {
    /// Converts between Cocoa global and Quartz global rects. The formula is the same in both directions.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The rect between two points, with positive width and height.
    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// `rect` moved by `offset`, kept inside `bounds`. The size never changes.
    public static func moved(_ rect: CGRect, by offset: CGVector, within bounds: CGRect) -> CGRect {
        var moved = rect.offsetBy(dx: offset.dx, dy: offset.dy)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return moved
    }

    /// When `point` is within `tolerance` of a corner of `rect`, the opposite corner: drag from it to resize.
    public static func oppositeCorner(of rect: CGRect, near point: CGPoint, tolerance: CGFloat) -> CGPoint? {
        let corners = [
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY)),
        ]
        return corners.first { hypot($0.0.x - point.x, $0.0.y - point.y) <= tolerance }?.1
    }

    /// The pixel rect in a screen image for a selection in view-local points.
    /// The pixels under both corners are inside it, the same pixels `pixel(at:)` shows in the
    /// magnifier, so what you point at is what you get. The result is whole pixels inside the image.
    public static func pixelRect(forSelection selection: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let sx = imageSize.width / viewSize.width
        let sy = imageSize.height / viewSize.height
        let left = (selection.minX * sx).rounded(.down)
        let right = (selection.maxX * sx).rounded(.down) + 1
        let top = ((viewSize.height - selection.maxY) * sy).rounded(.down)
        let bottom = ((viewSize.height - selection.minY) * sy).rounded(.down) + 1
        let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// The view-local points that `pixels` (from `pixelRect`) cover, to draw the selection as it will be cropped.
    public static func viewRect(forPixels pixels: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let sx = viewSize.width / imageSize.width
        let sy = viewSize.height / imageSize.height
        return CGRect(
            x: pixels.minX * sx,
            y: viewSize.height - pixels.maxY * sy,
            width: pixels.width * sx,
            height: pixels.height * sy
        )
    }

    /// The pixel under a view-local point, in image pixels.
    public static func pixel(at point: CGPoint, viewSize: CGSize, imageSize: CGSize) -> (x: Int, y: Int) {
        guard viewSize.width > 0, viewSize.height > 0 else { return (0, 0) }
        let x = Int((point.x * imageSize.width / viewSize.width).rounded(.down))
        let y = Int(((viewSize.height - point.y) * imageSize.height / viewSize.height).rounded(.down))
        return (min(max(x, 0), Int(imageSize.width) - 1), min(max(y, 0), Int(imageSize.height) - 1))
    }

    /// Moves `value` onto the nearest edge when it is within `tolerance`. Otherwise returns `value`.
    public static func snap(_ value: CGFloat, to edges: [CGFloat], tolerance: CGFloat) -> CGFloat {
        var best = value
        var bestDistance = tolerance
        for edge in edges {
            let distance = abs(edge - value)
            if distance <= bestDistance {
                best = edge
                bestDistance = distance
            }
        }
        return best
    }

    /// Snaps `point` to the screen edges and to window edges you can see at it.
    /// `windows` are frames front to back. A window edge counts only where it runs past the point
    /// (within `tolerance`) and no window in front of it covers it there, so the hidden edges of
    /// windows behind others never pull the selection away from what the magnifier shows.
    public static func snap(_ point: CGPoint, toWindows windows: [CGRect], bounds: CGRect, tolerance: CGFloat) -> CGPoint {
        func covered(_ edgePoint: CGPoint, before index: Int) -> Bool {
            windows[..<index].contains { front in
                front.minX < edgePoint.x && edgePoint.x < front.maxX && front.minY < edgePoint.y && edgePoint.y < front.maxY
            }
        }
        var xs: [CGFloat] = [bounds.minX, bounds.maxX]
        var ys: [CGFloat] = [bounds.minY, bounds.maxY]
        for (index, frame) in windows.enumerated() {
            if frame.minY - tolerance <= point.y, point.y <= frame.maxY + tolerance {
                let y = min(max(point.y, frame.minY), frame.maxY)
                xs += [frame.minX, frame.maxX].filter { !covered(CGPoint(x: $0, y: y), before: index) }
            }
            if frame.minX - tolerance <= point.x, point.x <= frame.maxX + tolerance {
                let x = min(max(point.x, frame.minX), frame.maxX)
                ys += [frame.minY, frame.maxY].filter { !covered(CGPoint(x: x, y: $0), before: index) }
            }
        }
        return CGPoint(x: snap(point.x, to: xs, tolerance: tolerance), y: snap(point.y, to: ys, tolerance: tolerance))
    }

    /// The file name for a capture, for example `Navi 2026-11-06 at 16.10.12.png`.
    public static func fileName(for date: Date, fileExtension: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Navi \(formatter.string(from: date)).\(fileExtension)"
    }

    /// A URL in `folder` for `name` that does not exist yet. Adds ` (2)`, ` (3)`, and so on when needed.
    public static func uniqueURL(in folder: URL, name: String, exists: (URL) -> Bool) -> URL {
        let first = folder.appending(path: name)
        guard exists(first) else { return first }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        while true {
            let candidate = folder.appending(path: ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)")
            if !exists(candidate) { return candidate }
            number += 1
        }
    }

    /// True when a press and release are close enough to count as a click, not a drag.
    public static func isClick(from press: CGPoint, to point: CGPoint, threshold: CGFloat) -> Bool {
        hypot(point.x - press.x, point.y - press.y) <= threshold
    }

    /// The rect between `a` (progress 0) and `b` (progress 1). Progress is clamped to 0...1.
    public static func interpolate(_ a: CGRect, _ b: CGRect, progress: CGFloat) -> CGRect {
        let t = min(max(progress, 0), 1)
        return CGRect(
            x: a.minX + (b.minX - a.minX) * t,
            y: a.minY + (b.minY - a.minY) * t,
            width: a.width + (b.width - a.width) * t,
            height: a.height + (b.height - a.height) * t
        )
    }

    /// Cubic ease-out: fast at the start, slow at the end. Input and output are 0...1.
    public static func easeOut(_ t: CGFloat) -> CGFloat {
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    /// Edit after capture: the top-left corner of the toolbar for an area, all in top-left points.
    /// Below the area when it fits, else above it, else inside its bottom edge. Centered on the
    /// area and kept `margin` inside the screen.
    public static func toolbarOrigin(below area: CGRect, toolbar: CGSize, in screen: CGSize, gap: CGFloat, margin: CGFloat) -> CGPoint {
        let centered = area.midX - toolbar.width / 2
        let x = min(max(centered, margin), max(margin, screen.width - toolbar.width - margin))
        let below = area.maxY + gap
        if below + toolbar.height <= screen.height - margin { return CGPoint(x: x, y: below) }
        let above = area.minY - gap - toolbar.height
        if above >= margin { return CGPoint(x: x, y: above) }
        let inside = min(area.maxY, screen.height - margin) - gap - toolbar.height
        return CGPoint(x: x, y: max(margin, inside))
    }
}
