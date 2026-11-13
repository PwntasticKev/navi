import Foundation

public struct PadStore: Sendable {
    public let url: URL

    public init(directory: URL) {
        url = directory.appending(path: "pad-state.json")
    }

    public init?(appGroup: String) {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        self.init(directory: directory)
    }

    public func read() throws -> PadState {
        guard FileManager.default.fileExists(atPath: url.path) else { return .off }
        return try JSONDecoder().decode(PadState.self, from: Data(contentsOf: url))
    }

    public func write(_ state: PadState) throws {
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
