import SwiftUI

enum NaviTheme {
    static let ink = Color(hex: 0x07080C)
    static let blue = Color(hex: 0x4078FF)
    static let violet = Color(hex: 0xA050FF)
    static let orange = Color(hex: 0xFF8C28)
    static let lavender = Color(hex: 0xB9C9FF)
    static let added = Color(hex: 0x9FF0C0)
    static let struck = Color(hex: 0xFF786E)
    static let recording = Color(hex: 0xFF5A4F)

    static let brand = LinearGradient(
        colors: [Color(hex: 0x8FB4FF), Color(hex: 0xC59BFF), Color(hex: 0xFFB37A)],
        startPoint: .leading, endPoint: .trailing
    )

    static let orb = RadialGradient(
        colors: [Color(hex: 0xA9C8FF), Color(hex: 0x4A74FF), Color(hex: 0x7B48FF)],
        center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 60
    )
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct AuroraBackground: View {
    var strength: Double = 1
    var anchor: UnitPoint = .center
    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                NaviTheme.ink
                blob(NaviTheme.blue, opacity: 0.42, size: size, x: drift ? 0.22 : 0.32, y: anchor.y)
                blob(NaviTheme.violet, opacity: 0.38, size: size, x: drift ? 0.78 : 0.66, y: anchor.y + 0.06)
                blob(NaviTheme.orange, opacity: 0.17, size: size, x: drift ? 0.46 : 0.56, y: anchor.y + 0.22)
            }
            .blur(radius: 36)
        }
        .clipped()
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func blob(_ color: Color, opacity: Double, size: CGSize, x: Double, y: Double) -> some View {
        let diameter = max(size.width, size.height) * 0.75
        return Circle()
            .fill(RadialGradient(
                colors: [color.opacity(opacity * strength), color.opacity(0)],
                center: .center, startRadius: 0, endRadius: diameter / 2
            ))
            .frame(width: diameter, height: diameter)
            .position(x: size.width * x, y: size.height * y)
    }
}

struct BrandWordmark: View {
    var size: CGFloat = 11

    var body: some View {
        Text("NAVI")
            .font(.system(size: size, weight: .semibold))
            .tracking(size * 0.14)
            .foregroundStyle(NaviTheme.brand)
    }
}

struct MicOrb: View {
    var diameter: CGFloat = 64
    var ripples = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            if ripples {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .stroke(Color(hex: 0x9CC3FF, opacity: 0.5), lineWidth: 1)
                        .scaleEffect(pulse ? 1.7 : 1)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(index) * 1.2),
                            value: pulse
                        )
                }
            }
            Circle()
                .fill(NaviTheme.orb)
                .shadow(color: Color(hex: 0x6E78FF, opacity: 0.6), radius: diameter * 0.4)
            Image(systemName: "mic.fill")
                .font(.system(size: diameter * 0.36, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { pulse = ripples }
    }
}

struct WaveLines: View {
    var level: Double
    var calm: Bool

    private struct Line {
        let colors: [Color]
        let amplitude: Double
        let frequency: Double
        let speed: Double
        let offset: Double
    }

    private static let lines = [
        Line(colors: [Color(hex: 0x6F9BFF), Color(hex: 0x9CC3FF)], amplitude: 1, frequency: 1.6, speed: 1.1, offset: 0),
        Line(colors: [Color(hex: 0xA06BFF), Color(hex: 0xD0A8FF)], amplitude: 0.75, frequency: 2.3, speed: -1.4, offset: 1.7),
        Line(colors: [Color(hex: 0xFF9D55), Color(hex: 0xFFC89A)], amplitude: 0.45, frequency: 3.1, speed: 1.9, offset: 3.1),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let swing = calm ? 2.5 : size.height * 0.36 * (0.22 + 0.78 * level) * (0.85 + 0.15 * sin(time * 2.3))
                context.blendMode = .plusLighter
                for line in Self.lines {
                    let path = Self.path(line, size: size, time: time, swing: swing)
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: line.colors[0], location: 0.2),
                            .init(color: line.colors[1], location: 0.5),
                            .init(color: line.colors[0], location: 0.8),
                            .init(color: .clear, location: 1),
                        ]),
                        startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)
                    )
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: line.colors[0], radius: 5))
                        layer.stroke(path, with: shading, lineWidth: calm ? 1.5 : 2.2)
                    }
                }
            }
        }
    }

    private static func path(_ line: Line, size: CGSize, time: Double, swing: Double) -> Path {
        var path = Path()
        let width = max(size.width, 1)
        for x in stride(from: 0, through: width, by: 2) {
            let u = x / width
            let envelope = pow(sin(Double.pi * u), 2.2)
            let phase = u * Double.pi * 2 * line.frequency + time * line.speed * 3 + line.offset
            let y = size.height / 2 + sin(phase) * swing * line.amplitude * envelope
            if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

struct GlassCircleButton: View {
    let symbol: String
    let label: String
    var dimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.08)))
                .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.35 : 1)
        .accessibilityLabel(label)
    }
}
