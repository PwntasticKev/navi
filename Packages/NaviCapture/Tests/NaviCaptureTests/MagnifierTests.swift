import CoreGraphics
import Foundation
import Testing

@testable import NaviCapture

@Suite struct MagnifierTests {
    @Test func styleKeepsSizeInRangeAndPixelsOdd() {
        #expect(MagnifierStyle(size: 10, pixelCount: 4) == MagnifierStyle(size: 64, pixelCount: 5))
        #expect(MagnifierStyle(size: 500, pixelCount: 40).size == 200)
        #expect(MagnifierStyle(size: 500, pixelCount: 40).pixelCount == 31)
        #expect(MagnifierStyle(size: 92, pixelCount: 12).pixelCount == 13)
    }

    @Test func dragUpGrowsAndDragRightZoomsIn() {
        let start = MagnifierStyle.standard
        #expect(start.resized(by: CGVector(dx: 0, dy: 30)).size == 106)
        #expect(start.resized(by: CGVector(dx: 0, dy: -30)).size == 64)
        #expect(start.resized(by: CGVector(dx: 48, dy: 0)).pixelCount == 5)
        #expect(start.resized(by: CGVector(dx: -24, dy: 0)).pixelCount == 11)
        #expect(start.resized(by: CGVector(dx: 5, dy: 0)) == start)
    }

    @Test func dragPastTheLimitsDoesNotBuildUp() {
        let start = MagnifierStyle.standard
        let clamped = start.clampedDrag(CGVector(dx: 1000, dy: 300))
        #expect(clamped == CGVector(dx: 48, dy: 124))
        #expect(start.resized(by: clamped) == MagnifierStyle(size: 200, pixelCount: 5))
        let back = start.clampedDrag(CGVector(dx: -1000, dy: -300))
        #expect(back == CGVector(dx: -264, dy: -12))
        #expect(start.resized(by: back) == MagnifierStyle(size: 64, pixelCount: 31))
    }

    @Test func styleIsSavedAndLoaded() throws {
        let defaults = try #require(UserDefaults(suiteName: "MagnifierTests"))
        defaults.removePersistentDomain(forName: "MagnifierTests")
        #expect(MagnifierStyle.load(from: defaults) == .standard)
        MagnifierStyle(size: 140, pixelCount: 19).save(to: defaults)
        #expect(MagnifierStyle.load(from: defaults) == MagnifierStyle(size: 140, pixelCount: 19))
        defaults.removePersistentDomain(forName: "MagnifierTests")
    }

    @Test func sitsRightAndBelowUntilAnEdge() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let panel = CGSize(width: 92, height: 114)
        #expect(MagnifierPlacement.side(for: CGPoint(x: 500, y: 400), panel: panel, in: bounds) == CGVector(dx: 1, dy: -1))
        #expect(MagnifierPlacement.side(for: CGPoint(x: 950, y: 400), panel: panel, in: bounds) == CGVector(dx: -1, dy: -1))
        #expect(MagnifierPlacement.side(for: CGPoint(x: 500, y: 60), panel: panel, in: bounds) == CGVector(dx: 1, dy: 1))
        #expect(MagnifierPlacement.side(for: CGPoint(x: 950, y: 60), panel: panel, in: bounds) == CGVector(dx: -1, dy: 1))
    }

    @Test func frameLeavesTheGapToTheCursor() {
        let frame = MagnifierPlacement.frame(
            for: CGPoint(x: 100, y: 300), panel: CGSize(width: 92, height: 114), side: CGVector(dx: 1, dy: -1)
        )
        #expect(frame == CGRect(x: 120, y: 166, width: 92, height: 114))
    }

    @Test func pixelsStayCenteredAtImageEdges() {
        let body = CGRect(x: 0, y: 0, width: 110, height: 110)
        let left = MagnifierPlacement.pixelDrawRect(
            source: CGRect(x: -3, y: 4, width: 11, height: 11), cropSize: CGSize(width: 8, height: 11), cell: 10, in: body
        )
        #expect(left == CGRect(x: 30, y: 0, width: 80, height: 110))
        let top = MagnifierPlacement.pixelDrawRect(
            source: CGRect(x: 4, y: -2, width: 11, height: 11), cropSize: CGSize(width: 11, height: 9), cell: 10, in: body
        )
        #expect(top == CGRect(x: 0, y: 0, width: 110, height: 90))
        let bottomRight = MagnifierPlacement.pixelDrawRect(
            source: CGRect(x: 95, y: 95, width: 11, height: 11), cropSize: CGSize(width: 5, height: 5), cell: 10, in: body
        )
        #expect(bottomRight == CGRect(x: 0, y: 60, width: 50, height: 50))
    }

    @Test func glideEasesBetweenSides() {
        let start = CGVector(dx: 1, dy: -1)
        let end = CGVector(dx: -1, dy: -1)
        #expect(MagnifierPlacement.glide(from: start, to: end, progress: 0) == start)
        #expect(MagnifierPlacement.glide(from: start, to: end, progress: 1) == end)
        #expect(MagnifierPlacement.glide(from: start, to: end, progress: 0.5).dx < 0)
    }

    @Test func hexReadsOnePixel() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        context.setFillColor(CGColor(srgbRed: 10 / 255, green: 132 / 255, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())
        #expect(PixelColor.read(from: image, x: 0, y: 1)?.hex == "#0A84FF")
        #expect(PixelColor.read(from: image, x: 1, y: 0)?.hex == "#FFFFFF")
        #expect(PixelColor.read(from: image, x: 2, y: 0) == nil)
    }
}

@Suite struct MagnifierMotionTests {
    let right = CGVector(dx: 1, dy: -1)
    let left = CGVector(dx: -1, dy: -1)

    @Test func flipGlidesThenFinishes() {
        var glide = MagnifierGlide()
        #expect(glide.side(toward: right, at: 0, animates: true) == right)
        #expect(glide.side(toward: left, at: 1, animates: true) == right)
        #expect(glide.isGliding)
        #expect(!glide.isFinished(at: 1.05))
        #expect(glide.isFinished(at: 1.2))
        #expect(glide.side(toward: left, at: 1.2, animates: true) == left)
        #expect(!glide.isGliding)
    }

    @Test func reduceMotionJumps() {
        var glide = MagnifierGlide()
        _ = glide.side(toward: right, at: 0, animates: false)
        #expect(glide.side(toward: left, at: 1, animates: false) == left)
        #expect(!glide.isGliding)
    }

    @Test func resetStopsAGlideAndForgetsTheSide() {
        var glide = MagnifierGlide()
        _ = glide.side(toward: right, at: 0, animates: true)
        _ = glide.side(toward: left, at: 1, animates: true)
        glide.reset()
        #expect(!glide.isGliding)
        #expect(glide.isFinished(at: 1))
        #expect(glide.side(toward: right, at: 2, animates: true) == right)
    }
}

@Suite struct MagnifierFooterTests {
    @Test func footerDropsPartsThatDoNotFit() {
        let hex: CGFloat = 43.3
        let coordinates: CGFloat = 58.7
        let small = MagnifierFooterLayout(width: MagnifierStyle.sizeRange.lowerBound, hexWidth: hex, coordinatesWidth: coordinates)
        #expect(MagnifierFooterLayout.inset * 2 + hex <= MagnifierStyle.sizeRange.lowerBound)
        #expect(small.showsSwatch == false && small.showsCoordinates == false)
        let standard = MagnifierFooterLayout(width: MagnifierStyle.standard.size, hexWidth: hex, coordinatesWidth: coordinates)
        #expect(standard.showsSwatch == true && standard.showsCoordinates == false)
        let wide = MagnifierFooterLayout(width: 150, hexWidth: hex, coordinatesWidth: coordinates)
        #expect(wide.showsSwatch == true && wide.showsCoordinates == true)
        let narrowCoordinates = MagnifierFooterLayout(width: 128, hexWidth: hex, coordinatesWidth: coordinates)
        #expect(!narrowCoordinates.showsCoordinates)
    }
}
