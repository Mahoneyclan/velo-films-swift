import Foundation

struct JSONLReader {
    private let decoder = JSONDecoder()

    func read<T: Decodable>(from url: URL) throws -> [T] {
        let data = try Data(contentsOf: url)
        return try data
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .map { try decoder.decode(T.self, from: Data($0)) }
    }
}
