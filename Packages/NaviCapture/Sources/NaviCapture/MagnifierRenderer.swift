import AppKit

@MainActor
enum MagnifierRenderer {
    static let footerHeight: CGFloat = 22
    static let cornerRadius: CGFloat = 14
    static let minimumGridCell: CGFloat = 4

    static func panelSize(for style: MagnifierStyle) -> CGSize {
        CGSize(width: style.size, height: style.size + footerHeight)
    }

    static func draw(image: CGImage, pixel: (x: Int, y: Int), pixelCount: Int, in frame: CGRect, context: CGContext) {
        let body = CGRect(x: frame.minX, y: frame.minY + footerHeight, width: frame.width, height: frame.height - footerHeight)
        let radius = cornerRadius
        let shape = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 16, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(shape)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        drawPixels(around: pixel, of: image, in: body, pixelCount: pixelCount, context: context)
        drawFooter(for: pixel, of: image, in: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: footerHeight), context: context)
        context.restoreGState()

        context.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: frame.insetBy(dx: -0.5, dy: -0.5), cornerWidth: radius + 0.5, cornerHeight: radius + 0.5, transform: nil))
        context.strokePath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(1.5)
        context.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.75, dy: 0.75), cornerWidth: radius - 0.75, cornerHeight: radius - 0.75, transform: nil))
        context.strokePath()
    }

    private static func drawPixels(around pixel: (x: Int, y: Int), of image: CGImage, in body: CGRect, pixelCount: Int, context: CGContext) {
        let cell = body.width / CGFloat(pixelCount)
        let half = pixelCount / 2
        let source = CGRect(x: pixel.x - half, y: pixel.y - half, width: pixelCount, height: pixelCount)
        if let crop = image.cropping(to: source) {
            let drawRect = MagnifierPlacement.pixelDrawRect(
                source: source, cropSize: CGSize(width: crop.width, height: crop.height), cell: cell, in: body
            )
            context.saveGState()
            context.interpolationQuality = .none
            context.draw(crop, in: drawRect)
            context.restoreGState()
        }

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.1).cgColor)
        context.setLineWidth(0.5)
        for index in 1..<pixelCount where cell >= minimumGridCell {
            let offset = CGFloat(index) * cell
            context.move(to: CGPoint(x: body.minX + offset, y: body.minY))
            context.addLine(to: CGPoint(x: body.minX + offset, y: body.maxY))
            context.move(to: CGPoint(x: body.minX, y: body.minY + offset))
            context.addLine(to: CGPoint(x: body.maxX, y: body.minY + offset))
        }
        context.strokePath()

        let center = CGRect(x: body.midX - cell / 2, y: body.midY - cell / 2, width: cell, height: cell)
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.8).cgColor)
        context.stroke(center.insetBy(dx: -1, dy: -1))
        context.setStrokeColor(NSColor.white.cgColor)
        context.stroke(center)
    }

    private static func drawFooter(for pixel: (x: Int, y: Int), of image: CGImage, in strip: CGRect, context: CGContext) {
        context.setFillColor(NSColor(white: 0.08, alpha: 0.92).cgColor)
        context.fill(strip)
        guard let color = PixelColor.read(from: image, x: pixel.x, y: pixel.y) else { return }
        let hex = color.hex as NSString
        let coordinates = "\(pixel.x), \(pixel.y)" as NSString
        let hexWidth = hex.size(withAttributes: footerAttributes).width
        let coordinatesWidth = coordinates.size(withAttributes: footerDimAttributes).width
        let widestCoordinates = "\(image.width - 1), \(image.height - 1)" as NSString
        let reservedWidth = max(coordinatesWidth, widestCoordinates.size(withAttributes: footerDimAttributes).width)
        let layout = MagnifierFooterLayout(width: strip.width, hexWidth: hexWidth, coordinatesWidth: reservedWidth)
        let inset = MagnifierFooterLayout.inset
        let baseline = strip.midY - footerFontHeight / 2
        var textX = strip.minX + inset

        if layout.showsSwatch {
            let size = MagnifierFooterLayout.swatchSize
            let swatch = CGRect(x: textX, y: strip.midY - size / 2, width: size, height: size)
            let swatchPath = CGPath(roundedRect: swatch, cornerWidth: 3, cornerHeight: 3, transform: nil)
            context.setFillColor(color.cgColor)
            context.addPath(swatchPath)
            context.fillPath()
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1)
            context.addPath(swatchPath)
            context.strokePath()
            textX = swatch.maxX + MagnifierFooterLayout.spacing
        }
        if !layout.showsSwatch && !layout.showsCoordinates {
            textX = strip.midX - hexWidth / 2
        }
        hex.draw(at: CGPoint(x: textX, y: baseline), withAttributes: footerAttributes)
        guard layout.showsCoordinates else { return }
        coordinates.draw(at: CGPoint(x: strip.maxX - inset - coordinatesWidth, y: baseline), withAttributes: footerDimAttributes)
    }

    private static let footerAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
        .foregroundColor: NSColor.white,
    ]
    private static let footerDimAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.55),
    ]
    private static let footerFontHeight = ("0" as NSString).size(withAttributes: footerAttributes).height
}
