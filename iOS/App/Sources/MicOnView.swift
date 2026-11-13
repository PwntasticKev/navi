import SwiftUI

struct MicOnView: View {
    let host: SessionHost
    let close: () -> Void
    @State private var sweep = false

    var body: some View {
        ZStack {
            AuroraBackground(anchor: UnitPoint(x: 0.5, y: 0.35)).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done", action: close)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer().frame(height: 90)
                MicOrb(diameter: 120, ripples: true)
                Text("Mic is on")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.4)
                    .padding(.top, 44)
                Text("Go back and start talking.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 8)
                Label("Stays ready for 15 min", systemImage: "timer")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.07)))
                    .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1))
                    .padding(.top, 22)
                Spacer()
                VStack(spacing: 12) {
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .frame(width: 140, height: 5)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(LinearGradient(colors: [.clear, .white], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 44, height: 5)
                                .offset(x: sweep ? 140 : -44)
                        }
                        .clipShape(Capsule())
                    Text("Swipe right on the bar, or tap the app name at the top left")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
            }
        }
        .foregroundStyle(.white)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: false)) { sweep = true }
        }
    }
}
