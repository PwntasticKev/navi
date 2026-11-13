import Foundation

enum PadConfig {
    static let fallbackAppGroup = "group.com.donovanhiland.navi.ios"
    static let startURL = URL(string: "navi-ios://start")!

    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "NaviAppGroup") as? String ?? fallbackAppGroup
    }

    static var signalPrefix: String { appGroup }
}
