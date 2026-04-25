import Foundation

struct JSONLWriter {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = []
        return e
    }()

    func write<T: Encodable>(rows: [T], to url: URL) throws {
        let lines = try rows.map { try encoder.encode($0) }
        let data = lines.joined(separator: Data("\n".utf8))
        try data.write(to: url, options: .atomic)
    }
}

private extension Array where Element == Data {
    func joined(separator: Data) -> Data {
        guard !isEmpty else { return Data() }
        return dropFirst().reduce(first!) { $0 + separator + $1 }
    }
}
