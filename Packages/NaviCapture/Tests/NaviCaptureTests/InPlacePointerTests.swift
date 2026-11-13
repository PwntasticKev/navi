import CoreGraphics
import Testing

@testable import NaviCapture

@MainActor
struct InPlacePointerTests {
    private static let hole = CGRect(x: 100, y: 100, width: 400, height: 300)
    private static let toolbar = CGRect(x: 100, y: 410, width: 400, height: 44)

    private func pointer(_ point: CGPoint, canAdjust: Bool = true) -> AnnotateModel.Pointer {
        InPlaceAnnotateView.pointer(
            at: point, hole: Self.hole, toolbar: Self.toolbar, canAdjust: canAdjust, showsMoveTab: false,
            inside: { _ in .crosshair }
        )
    }

    @Test func toolbarShowsTheArrowEvenInsideTheResizeRing() {
        #expect(pointer(CGPoint(x: 300, y: 412)) == .arrow)
    }

    @Test func insideTheShotTheCanvasDecides() {
        #expect(pointer(CGPoint(x: 300, y: 250)) == .crosshair)
    }

    @Test func edgesShowResizeArrows() {
        #expect(pointer(CGPoint(x: 96, y: 250)) == .resize(.left))
        #expect(pointer(CGPoint(x: 300, y: 98)) == .resize(.top))
        #expect(pointer(CGPoint(x: 96, y: 98)) == .resize(.topLeft))
    }

    @Test func outsideIsTheArrow() {
        #expect(pointer(CGPoint(x: 20, y: 20)) == .arrow)
        #expect(pointer(CGPoint(x: 96, y: 250), canAdjust: false) == .arrow)
    }
}
