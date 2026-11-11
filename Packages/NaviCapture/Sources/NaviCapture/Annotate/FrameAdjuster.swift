import AppKit
import SwiftUI

/// Edit after capture: the frame around the canvas, so a rough first drag can be fixed.
///
/// Soft corner brackets sit just outside the frame, so they never cover the shot and still show on
/// white. When the pointer comes near (`reveal` 0 → 1) they grow, and ticks on all four edges and a
/// move tab above the frame (move icon and pixel size) fade in. Drag any edge or corner, the top one
/// too, to resize; drag the tab to move. The tab sits apart from the edge so the two never mix.
/// After rotate, flip, or resize the frame is locked, and only the line shows.
struct FrameAdjuster: View {
    /// The canvas on the screen, in top-left points.
    let frame: CGRect
    let pixelSize: CGSize
    let screenSize: CGSize
    let canAdjust: Bool
    /// 0 at rest, 1 while the pointer is near or a drag is on.
    let reveal: CGFloat
    /// A drag of the frame started or ended.
    let onDragging: (Bool) -> Void
    /// The frame during a drag, in top-left points.
    let onChange: (CGRect) -> Void

    static let gap: CGFloat = 4
    /// How far from the line a drag still grabs an edge or corner (outside the frame).
    static let grab: CGFloat = 10
    /// How far inside the frame an edge can be grabbed. Small, so drawing near the edge still works.
    private static let grabInside: CGFloat = 4
    private static let minSize: CGFloat = 8
    private static let shadow = Color.black.opacity(0.45)

    @State private var dragStart: (handle: CaptureGeometry.FrameHandle?, frame: CGRect)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                .frame(width: frame.width + 1, height: frame.height + 1)
                .offset(x: frame.minX - 0.5, y: frame.minY - 0.5)
                .allowsHitTesting(false)
            if canAdjust {
                marks
                grabRing
                moveTab
            }
        }
    }

    // MARK: Look

    private var marks: some View {
        let outer = frame.insetBy(dx: -Self.gap, dy: -Self.gap)
        return ZStack(alignment: .topLeading) {
            FrameBrackets(rect: outer, length: 10 + 5 * reveal)
                .stroke(Color.white.opacity(0.7 + 0.3 * reveal), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            FrameTicks(rect: outer, inner: frame)
                .stroke(Color.white.opacity(0.9 * reveal), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .shadow(color: Self.shadow, radius: 1)
        .allowsHitTesting(false)
    }

    // MARK: Drag

    /// A band around the line: outside up to `grab`, inside only `grabInside`.
    private var grabRing: some View {
        let outer = frame.insetBy(dx: -Self.grab, dy: -Self.grab)
        let inner = frame.insetBy(dx: Self.grabInside, dy: Self.grabInside)
        return Color.clear
            .contentShape(GrabRing(outer: outer, inner: inner), eoFill: true)
            .onContinuousHover(coordinateSpace: .named(InPlaceAnnotateView.space)) { phase in
                guard dragStart == nil, case let .active(point) = phase, let handle = handle(at: point) else { return }
                Self.cursor(for: handle).set()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named(InPlaceAnnotateView.space))
                    .onChanged { value in
                        let start = dragStart ?? begin(handle(at: value.startLocation))
                        guard let handle = start.handle else { return }
                        onChange(CaptureGeometry.resized(
                            start.frame, handle: handle, to: value.location, within: screenBounds, minSize: Self.minSize
                        ))
                    }
                    .onEnded { _ in end() }
            )
    }

    /// A tab above the frame, apart from the top edge, with a move icon and the pixel size. Drag it
    /// to move the frame. Inside the top edge when there is no room above.
    private var moveTab: some View {
        let zone = Self.moveTabZone(of: frame)
        return HStack(spacing: 4) {
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 9, weight: .semibold))
            Text(verbatim: "\(Int(pixelSize.width)) × \(Int(pixelSize.height))")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .frame(height: Self.tabHeight)
        .background(Color.black.opacity(0.65), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
        .fixedSize()
        .contentShape(Capsule())
        .opacity(reveal)
        .onHover { inside in if inside { NSCursor.openHand.set() } }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(InPlaceAnnotateView.space))
                .onChanged { value in
                    let start = dragStart ?? begin(nil)
                    NSCursor.closedHand.set()
                    onChange(CaptureGeometry.moved(
                        start.frame, by: CGVector(dx: value.translation.width, dy: value.translation.height), within: screenBounds
                    ))
                }
                .onEnded { _ in
                    end()
                    NSCursor.openHand.set()
                }
        )
        .position(x: zone.midX, y: zone.midY)
    }

    static let tabHeight: CGFloat = 20
    /// Space between the tab and the frame line. More than `grab`, so the tab never covers the top edge.
    private static let tabGap: CGFloat = grab + 4
    /// Wide enough for the widest tab (icon and a 5 × 4 digit size).
    private static let tabZoneWidth: CGFloat = 130

    /// Where the move tab sits: above the frame, clear of the top edge's grab band, or inside the
    /// top edge (below its band) when the frame is too close to the top of the screen.
    static func moveTabZone(of frame: CGRect) -> CGRect {
        let fitsAbove = frame.minY >= tabGap + tabHeight
        let y = fitsAbove ? frame.minY - tabGap - tabHeight : frame.minY + grabInside + 6
        return CGRect(x: frame.midX - tabZoneWidth / 2, y: y, width: tabZoneWidth, height: tabHeight)
    }

    private var screenBounds: CGRect { CGRect(origin: .zero, size: screenSize) }

    private func handle(at point: CGPoint) -> CaptureGeometry.FrameHandle? {
        CaptureGeometry.frameHandle(of: frame, near: point, tolerance: Self.grab)
    }

    private func begin(_ handle: CaptureGeometry.FrameHandle?) -> (handle: CaptureGeometry.FrameHandle?, frame: CGRect) {
        let start = (handle, frame)
        dragStart = start
        onDragging(true)
        return start
    }

    private func end() {
        guard dragStart != nil else { return }
        dragStart = nil
        onDragging(false)
    }

    static func cursor(for handle: CaptureGeometry.FrameHandle) -> NSCursor {
        let position: NSCursor.FrameResizePosition = switch handle {
        case .top: .top
        case .bottom: .bottom
        case .left: .left
        case .right: .right
        case .topLeft: .topLeft
        case .topRight: .topRight
        case .bottomLeft: .bottomLeft
        case .bottomRight: .bottomRight
        }
        return .frameResize(position: position, directions: .all)
    }
}

/// Rounded L brackets on the four corners of `rect`. `length` animates.
private struct FrameBrackets: Shape {
    var rect: CGRect
    var length: CGFloat

    var animatableData: CGFloat {
        get { length }
        set { length = newValue }
    }

    func path(in _: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),
        ]
        for (corner, sx, sy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + sy * length))
            path.addArc(tangent1End: corner, tangent2End: CGPoint(x: corner.x + sx * length, y: corner.y), radius: 4)
            path.addLine(to: CGPoint(x: corner.x + sx * length, y: corner.y))
        }
        return path
    }
}

/// Short ticks at the middle of each edge, so every edge reads as one you can drag.
/// Only on edges long enough that a tick does not crowd the brackets.
private struct FrameTicks: Shape {
    let rect: CGRect
    let inner: CGRect

    func path(in _: CGRect) -> Path {
        var path = Path()
        let half: CGFloat = 7
        let minEdge: CGFloat = 60
        if inner.width >= minEdge {
            for y in [rect.minY, rect.maxY] {
                path.move(to: CGPoint(x: inner.midX - half, y: y))
                path.addLine(to: CGPoint(x: inner.midX + half, y: y))
            }
        }
        if inner.height >= minEdge {
            for x in [rect.minX, rect.maxX] {
                path.move(to: CGPoint(x: x, y: inner.midY - half))
                path.addLine(to: CGPoint(x: x, y: inner.midY + half))
            }
        }
        return path
    }
}

/// The area between two rects, for hit testing with the even-odd rule.
private struct GrabRing: Shape {
    let outer: CGRect
    let inner: CGRect

    func path(in _: CGRect) -> Path {
        var path = Path(outer)
        if !inner.isNull, inner.width > 0, inner.height > 0 { path.addRect(inner) }
        return path
    }
}
