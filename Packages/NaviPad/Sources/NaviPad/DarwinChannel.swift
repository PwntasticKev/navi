import CoreFoundation
import Foundation
import Synchronization

public enum PadSignal: String, CaseIterable, Sendable {
    case start
    case stop
    case cancel
    case ping
    case pong
    case changed

    public func name(prefix: String) -> String {
        "\(prefix).pad.\(rawValue)"
    }
}

public final class DarwinChannel: Sendable {
    public typealias Handler = @Sendable (PadSignal) -> Void

    private let prefix: String
    private let handlers = Mutex<[String: PadSignal]>([:])
    private let handler = Mutex<Handler?>(nil)

    public init(prefix: String) {
        self.prefix = prefix
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque()
        )
    }

    public func post(_ signal: PadSignal) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(signal.name(prefix: prefix) as CFString), nil, nil, true
        )
    }

    public func observe(_ signals: [PadSignal], handler newHandler: @escaping Handler) {
        handler.withLock { $0 = newHandler }
        for signal in signals {
            let name = signal.name(prefix: prefix)
            let isNew = handlers.withLock { names -> Bool in
                defer { names[name] = signal }
                return names[name] == nil
            }
            guard isNew else { continue }
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    let channel = Unmanaged<DarwinChannel>.fromOpaque(observer).takeUnretainedValue()
                    channel.deliver(name.rawValue as String)
                },
                name as CFString, nil, .deliverImmediately
            )
        }
    }

    func deliver(_ name: String) {
        guard let signal = handlers.withLock({ $0[name] }), let current = handler.withLock({ $0 }) else { return }
        current(signal)
    }
}
