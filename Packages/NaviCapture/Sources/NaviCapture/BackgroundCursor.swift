import AppKit
import OSLog

@MainActor
enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private static let log = Logger(subsystem: "com.donovanhiland.navi", category: "Capture")
    private static let propertyKey = "SetsCursorInBackground" as CFString

    private static let functions: (DefaultConnection, SetProperty)? = {
        let everyImage = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connection = dlsym(everyImage, "_CGSDefaultConnection"),
              let setProperty = dlsym(everyImage, "CGSSetConnectionProperty")
        else { return nil }
        return (unsafeBitCast(connection, to: DefaultConnection.self), unsafeBitCast(setProperty, to: SetProperty.self))
    }()

    static func setEnabled(_ enabled: Bool) {
        guard let (defaultConnection, setProperty) = functions else {
            log.error("SetsCursorInBackground is not available; the overlay keeps the normal pointer")
            return
        }
        let connection = defaultConnection()
        let value: CFBoolean = enabled ? kCFBooleanTrue : kCFBooleanFalse
        let status = setProperty(connection, connection, propertyKey, value)
        if status != 0 { log.error("SetsCursorInBackground failed: \(status)") }
    }
}
