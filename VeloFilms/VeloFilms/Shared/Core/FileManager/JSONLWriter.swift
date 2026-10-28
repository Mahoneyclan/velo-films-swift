// JSONLWriter.swift
// Writes pipeline step output as JSON Lines (one compact JSON object per line).

import Foundation

/// Encodes rows as JSON Lines.
struct JSONLWriter {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()

    /// Writes `rows` to `url`, one per line, replacing any existing file atomically.
    /// - Parameters:
    ///   - rows: The rows to write, in order.
    ///   - url: Destination file.
    /// - Throws: Encoding or file write errors; on failure the previous file is left unchanged.
    func write<T: Encodable>(rows: [T], to url: URL) throws {
        let lines = try rows.map { try encoder.encode($0) }
        let data = lines.joined(separator: Data("\n".utf8))
        try data.write(to: url, options: .atomic)
    }
}

private extension Array where Element == Data {
    func joined(separator: Data) -> Data {
        guard !isEmpty else { return Data() }
        // Safe: the guard above ensures the array is not empty.
        return dropFirst().reduce(first!) { $0 + separator + $1 }
    }
}
