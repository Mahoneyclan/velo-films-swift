import Foundation

/// Writes Codable structs to CSV files.
/// Uses reflection via CodingKey to produce column-ordered output.
struct CSVWriter {

    func write<T: Encodable>(rows: [T], to url: URL) throws {
        guard !rows.isEmpty else {
            try "".write(to: url, atomically: true, encoding: .utf8)
            return
        }

        // Encode each row to a dictionary, then flatten to CSV
        let encoder = JSONEncoder()
        var csvLines: [String] = []

        for (i, row) in rows.enumerated() {
            let data = try encoder.encode(row)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any?]
            if i == 0 {
                csvLines.append(json.keys.sorted().joined(separator: ","))
            }
            let values = json.keys.sorted().map { key -> String in
                guard let val = json[key], val != nil else { return "" }
                let s = "\(val!)"
                if s.contains(",") || s.contains("\"") || s.contains("\n") {
                    return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return s
            }
            csvLines.append(values.joined(separator: ","))
        }

        let csv = csvLines.joined(separator: "\n")
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }
}
