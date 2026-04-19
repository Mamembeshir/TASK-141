import Foundation
import zlib

enum XLSXParseError: LocalizedError {
    case missingSheetFile
    case xmlParseError

    var errorDescription: String? {
        switch self {
        case .missingSheetFile: return "XLSX is missing sheet1.xml — not a valid workbook."
        case .xmlParseError:    return "Failed to parse XLSX XML content."
        }
    }
}

/// Minimal XLSX reader: ZIP local-file-header scan + NSXMLParser.
/// Handles stored (method 0) and raw-deflate (method 8) entries.
/// No external dependencies — uses Foundation's XMLParser and Darwin's zlib.
enum XLSXParser {

    // MARK: - Public

    /// Parses XLSX binary data and returns `(headers, rows)`.
    /// The first sheet row becomes the header keys; subsequent rows are
    /// returned as `[header: value]` dictionaries.
    static func parse(data: Data) throws -> (headers: [String], rows: [[String: String]]) {
        let sharedRaw = extractEntry(named: "xl/sharedStrings.xml", from: data)
        guard let sheetRaw = extractEntry(named: "xl/worksheets/sheet1.xml", from: data) else {
            throw XLSXParseError.missingSheetFile
        }
        let shared = sharedRaw.flatMap { parseSharedStrings($0) } ?? []
        return try parseSheet(sheetRaw, sharedStrings: shared)
    }

    // MARK: - ZIP entry extraction

    /// Walks the ZIP local file headers and returns the decompressed bytes
    /// for the first entry whose name matches `targetName`, or `nil`.
    private static func extractEntry(named targetName: String, from zip: Data) -> Data? {
        var offset = 0
        while offset + 30 <= zip.count {
            // Local file header signature: PK\x03\x04
            guard zip[offset] == 0x50, zip[offset + 1] == 0x4B,
                  zip[offset + 2] == 0x03, zip[offset + 3] == 0x04 else {
                offset += 1
                continue
            }
            let method     = readUInt16(zip, at: offset + 8)
            let compSize   = Int(readUInt32(zip, at: offset + 18))
            let uncompSize = Int(readUInt32(zip, at: offset + 22))
            let nameLen    = Int(readUInt16(zip, at: offset + 26))
            let extraLen   = Int(readUInt16(zip, at: offset + 28))
            let dataStart  = offset + 30 + nameLen + extraLen

            guard dataStart + compSize <= zip.count else { offset += 4; continue }

            let nameRange = (offset + 30) ..< (offset + 30 + nameLen)
            if let name = String(bytes: zip[nameRange], encoding: .utf8), name == targetName {
                let compData = zip.subdata(in: dataStart ..< (dataStart + compSize))
                switch method {
                case 0:  return compData                                        // stored
                case 8:  return rawInflate(compData, uncompressedSize: uncompSize) // deflate
                default: return nil
                }
            }
            offset = dataStart + compSize
        }
        return nil
    }

    // MARK: - Raw DEFLATE (ZIP uses deflate without zlib/gzip header)

    private static func rawInflate(_ data: Data, uncompressedSize: Int) -> Data? {
        let outSize = max(uncompressedSize, data.count * 4 + 1024)
        var output  = Data(count: outSize)
        let written: Int = data.withUnsafeBytes { srcBuf -> Int in
            guard let src = srcBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
            else { return 0 }
            return output.withUnsafeMutableBytes { dstBuf -> Int in
                guard let dst = dstBuf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else { return 0 }
                var stream            = z_stream()
                stream.next_in        = UnsafeMutablePointer(mutating: src)
                stream.avail_in       = uInt(data.count)
                stream.next_out       = dst
                stream.avail_out      = uInt(outSize)
                // -15 selects raw inflate (no zlib/gzip wrapper check)
                guard inflateInit2_(&stream, -15, ZLIB_VERSION,
                                    Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return 0 }
                _ = zlib.inflate(&stream, Z_FINISH)
                inflateEnd(&stream)
                return Int(stream.total_out)
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    // MARK: - Little-endian helpers

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])       | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    // MARK: - sharedStrings.xml

    private static func parseSharedStrings(_ data: Data) -> [String]? {
        let delegate = SharedStringsDelegate()
        let parser   = XMLParser(data: data)
        parser.delegate = delegate
        return parser.parse() ? delegate.strings : nil
    }

    // MARK: - sheet1.xml

    private static func parseSheet(
        _ data: Data,
        sharedStrings: [String]
    ) throws -> (headers: [String], rows: [[String: String]]) {
        let delegate = SheetDelegate(sharedStrings: sharedStrings)
        let parser   = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw XLSXParseError.xmlParseError }

        let grid    = delegate.gridRows
        guard let headers = grid.first else { return ([], []) }
        let rows: [[String: String]] = grid.dropFirst().map { cols in
            var dict = [String: String]()
            for (i, key) in headers.enumerated() where i < cols.count {
                dict[key] = cols[i]
            }
            return dict
        }
        return (headers, rows)
    }
}

// MARK: - SAX delegates (file-private)

private final class SharedStringsDelegate: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var inT        = false
    private var buf        = ""

    func parser(_ parser: XMLParser, didStartElement el: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if el == "t" { inT = true; buf = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { buf += string }
    }

    func parser(_ parser: XMLParser, didEndElement el: String,
                namespaceURI: String?, qualifiedName: String?) {
        if el == "t" { strings.append(buf); inT = false }
    }
}

/// Parses `sheet1.xml` into a two-dimensional grid of strings.
/// Handles shared-string cells (type `s`), inline-string cells
/// (type `inlineStr`), and plain value cells (numbers, dates).
private final class SheetDelegate: NSObject, XMLParserDelegate {
    let sharedStrings: [String]
    var gridRows: [[String]] = []

    private var currentRow:  [String] = []
    private var cellType     = ""   // "s" | "inlineStr" | ""
    private var cellValue    = ""
    private var inValue      = false
    private var inInlineStr  = false

    init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }

    func parser(_ parser: XMLParser, didStartElement el: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch el {
        case "row":
            currentRow = []
        case "c":
            cellType  = attributes["t"] ?? ""
            cellValue = ""
            inValue   = false
        case "v":
            inValue   = true
            cellValue = ""
        case "t" where inInlineStr || cellType == "inlineStr":
            inValue   = true
            cellValue = ""
        case "is":
            inInlineStr = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue { cellValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement el: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch el {
        case "v":
            inValue = false
        case "t" where inInlineStr:
            inValue = false
        case "is":
            inInlineStr = false
        case "c":
            if cellType == "s", let idx = Int(cellValue), idx < sharedStrings.count {
                currentRow.append(sharedStrings[idx])
            } else {
                currentRow.append(cellValue)
            }
            inValue = false
        case "row":
            if !currentRow.isEmpty { gridRows.append(currentRow) }
        default: break
        }
    }
}
