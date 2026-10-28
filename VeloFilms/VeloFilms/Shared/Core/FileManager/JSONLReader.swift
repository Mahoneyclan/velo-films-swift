// JSONLReader.swift
// Reads JSON Lines files (one JSON object per line) produced by the pipeline steps.

import Foundation

/// Decodes a JSON Lines file into an array of rows.
struct JSONLReader {
    private let decoder = JSONDecoder()

    /// Reads every non-empty line of `url` as one `T`.
    /// - Parameter url: The `.jsonl` file.
    /// - Returns: The decoded rows, in file order.
    /// - Throws: File read errors, or a `DecodingError` for the first line that doesn't match `T` (no partial result).
    /// - Note: Loads the whole file into memory; files are small (one row per sample point).
    func read<T: Decodable>(from url: URL) throws -> [T] {
        let data = try Data(contentsOf: url)
        return try data
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .map { try decoder.decode(T.self, from: Data($0)) }
    }
}
