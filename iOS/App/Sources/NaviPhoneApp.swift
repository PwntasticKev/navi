import SwiftUI

@main
struct NaviPhoneApp: App {
    @State private var host = SessionHost()
    @State private var showsMicOn = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView(host: host)
                .fullScreenCover(isPresented: $showsMicOn) {
                    MicOnView(host: host) { showsMicOn = false }
                }
                .onOpenURL { url in
                    guard url.host() == PadConfig.startURL.host() else { return }
                    Task {
                        await host.startSession()
                        showsMicOn = host.isWarm
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { showsMicOn = false }
                }
                .preferredColorScheme(.dark)
        }
    }
}
