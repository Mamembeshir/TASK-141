import Foundation

/// Lightweight RFC 4180-compliant CSV parser.
enum CSVParser {

    struct ParseResult {
        let headers: [String]
        let rows: [[String: String]]
        let parseErrors: [String]
    }

    /// Parses a CSV string into headers + rows.
    static func parse(_ csvString: String) -> ParseResult {
        var lines = csvString
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .init(charactersIn: "\r")) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return ParseResult(headers: [], rows: [], parseErrors: ["Empty file"])
        }

        let headers = parseRow(lines.removeFirst())
        var rows: [[String: String]] = []
        var parseErrors: [String] = []

        for (index, line) in lines.enumerated() {
            let rowNumber = index + 2  // 1-indexed, row 1 is header
            let values = parseRow(line)
            if values.count != headers.count {
                parseErrors.append("Row \(rowNumber): Expected \(headers.count) columns, found \(values.count)")
                continue
            }
            var dict: [String: String] = [:]
            for (i, header) in headers.enumerated() {
                dict[header] = values[i]
            }
            rows.append(dict)
        }

        return ParseResult(headers: headers, rows: rows, parseErrors: parseErrors)
    }

    // MARK: - Row Parsing (RFC 4180)

    private static func parseRow(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex

        while i < line.endIndex {
            let ch = line[i]

            if inQuotes {
                if ch == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        i = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                } else if ch == "," {
                    fields.append(current)
                    current = ""
                } else {
                    current.append(ch)
                }
            }
            i = line.index(after: i)
        }
        fields.append(current)
        return fields
    }

    /// Escapes a field value for CSV output.
    static func escapeField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Builds a CSV string from headers and rows.
    static func build(headers: [String], rows: [[String: String]]) -> String {
        var lines: [String] = [headers.map(escapeField).joined(separator: ",")]
        for row in rows {
            let values = headers.map { escapeField(row[$0] ?? "") }
            lines.append(values.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
