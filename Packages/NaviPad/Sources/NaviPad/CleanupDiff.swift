import Foundation

public enum DiffPiece: Equatable, Sendable {
    case same(String)
    case removed(String)
    case added(String)
}

public enum CleanupDiff {
    static let maximumCells = 250_000

    public static func pieces(raw: String, cleaned: String) -> [DiffPiece] {
        let old = words(raw)
        let new = words(cleaned)
        guard !old.isEmpty else { return new.isEmpty ? [] : [.added(new.joined(separator: " "))] }
        guard !new.isEmpty else { return [.removed(old.joined(separator: " "))] }
        guard old.count * new.count <= maximumCells else { return [.same(new.joined(separator: " "))] }
        return merge(walk(old: old, new: new))
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func key(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func walk(old: [String], new: [String]) -> [DiffPiece] {
        let a = old.map(key)
        let b = new.map(key)
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var pieces: [DiffPiece] = []
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                pieces.append(.same(new[j]))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                pieces.append(.removed(old[i]))
                i += 1
            } else {
                pieces.append(.added(new[j]))
                j += 1
            }
        }
        pieces += old[i...].map(DiffPiece.removed)
        pieces += new[j...].map(DiffPiece.added)
        return pieces
    }

    private static func merge(_ pieces: [DiffPiece]) -> [DiffPiece] {
        pieces.reduce(into: [DiffPiece]()) { result, piece in
            guard let last = result.last else { return result.append(piece) }
            switch (last, piece) {
            case let (.same(a), .same(b)): result[result.count - 1] = .same(a + " " + b)
            case let (.removed(a), .removed(b)): result[result.count - 1] = .removed(a + " " + b)
            case let (.added(a), .added(b)): result[result.count - 1] = .added(a + " " + b)
            default: result.append(piece)
            }
        }
    }
}
