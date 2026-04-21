import Foundation

/// Reads CSV files into Decodable structs.
struct CSVReader {

    func read<T: Decodable>(from url: URL) throws -> [T] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard lines.count >= 2 else { return [] }

        let headers = parseCSVLine(lines[0])
        var results: [T] = []
        let decoder = JSONDecoder()

        for line in lines.dropFirst() {
            let values = parseCSVLine(line)
            guard values.count == headers.count else { continue }

            var dict: [String: Any] = [:]
            for (header, value) in zip(headers, values) {
                if value.isEmpty {
                    dict[header] = NSNull()
                } else if let i = Int(value) {
                    dict[header] = i
                } else if let d = Double(value) {
                    dict[header] = d
                } else if value == "True" || value == "true" {
                    dict[header] = true
                } else if value == "False" || value == "false" {
                    dict[header] = false
                } else {
                    dict[header] = value
                }
            }

            let rowData = try JSONSerialization.data(withJSONObject: dict)
            let row = try decoder.decode(T.self, from: rowData)
            results.append(row)
        }
        return results
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let c = line[i]
            if c == "\"" {
                let next = line.index(after: i)
                if inQuotes && next < line.endIndex && line[next] == "\"" {
                    current.append("\"")
                    i = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if c == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(c)
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }
}
