import CoreData
import Foundation

/// CSV import/export pipeline (PRD 8.7, questions.md 5.x).
/// Import is row-independent (partial success, IMP-05). Export supports
/// field-level masking via `MaskingHelper`.
final class ImportExportService {

    static let shared = ImportExportService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let productRepo: ProductRepository
    private let productService: ProductService

    init(context: NSManagedObjectContext) {
        self.context = context
        self.productRepo = ProductRepository(context: context)
        self.productService = ProductService(context: context)
    }

    // MARK: - Import

    struct RowError: Equatable {
        let row: Int
        let field: String
        let reason: String
        let score: Int
    }

    struct ImportReport: Equatable {
        let imported: Int
        let rejected: Int
        let errors: [RowError]
    }

    /// Imports a products CSV with columns:
    /// `spuName,barcode,stemCount,wrapType,color,priceCents,isTaxable`.
    /// Row quality score <70 is rejected (IMP-02 / questions.md 5.1).
    /// Valid rows land in Core Data; invalid rows come back in the report
    /// (IMP-04/05 — partial success, per-row report).
    @discardableResult
    func importProductsCSV(at url: URL, actor: User) throws -> ImportReport {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.parseFailure(reason: "Not UTF-8")
        }
        let parse = CSVParser.parse(content)
        return try processImportRows(parse.rows, actor: actor)
    }

    /// Imports products from an XLSX file. The first sheet's first row is
    /// treated as column headers; subsequent rows use the same field names
    /// as the CSV import (`spuName`, `barcode`, `priceCents`, etc.).
    @discardableResult
    func importProductsXLSX(at url: URL, actor: User) throws -> ImportReport {
        let data = try Data(contentsOf: url)
        let (_, rows) = try XLSXParser.parse(data: data)
        return try processImportRows(rows, actor: actor)
    }

    // MARK: - Shared row processing (CSV + XLSX)

    private func processImportRows(_ rows: [[String: String]], actor: User) throws -> ImportReport {
        var errors: [RowError] = []
        var imported = 0

        for (idx, raw) in rows.enumerated() {
            let rowNumber = idx + 2  // 1-indexed; header is row 1
            let score = qualityScore(row: raw)
            if score < AppConfiguration.importQualityMinScore {
                errors.append(.init(row: rowNumber, field: "_score",
                                    reason: "Quality score \(score) below minimum",
                                    score: score))
                continue
            }
            guard let name = raw["spuName"].nilIfEmpty,
                  let barcode = raw["barcode"].nilIfEmpty,
                  let priceStr = raw["priceCents"].nilIfEmpty,
                  let price = Int64(priceStr) else {
                errors.append(.init(row: rowNumber, field: "required",
                                    reason: "Missing required field", score: score))
                continue
            }
            if (try? productRepo.barcodeExists(barcode)) == true {
                errors.append(.init(row: rowNumber, field: "barcode",
                                    reason: "Duplicate barcode \(barcode)", score: score))
                continue
            }

            do {
                let spu = try productService.createSPU(
                    name: name, description: nil,
                    category: raw["category"], actor: actor
                )
                try productService.createSKU(
                    spuID: spu.id, barcode: barcode,
                    stemCount: Int16(raw["stemCount"] ?? "") ?? 0,
                    wrapType: raw["wrapType"], color: raw["color"],
                    priceCents: price,
                    isTaxable: (raw["isTaxable"]?.lowercased() ?? "true") == "true",
                    actor: actor
                )
                imported += 1
            } catch {
                errors.append(.init(row: rowNumber, field: "_import",
                                    reason: error.localizedDescription, score: score))
            }
        }

        AuditService.shared.logImport(
            actorID: actor.id, importedCount: imported,
            rejectedCount: errors.count, context: context
        )
        try context.save()

        let report = ImportReport(imported: imported, rejected: errors.count, errors: errors)
        persistImportReport(report, actorID: actor.id)
        return report
    }

    /// Serialises the import report to a JSON file in the exports directory so
    /// it survives the process and can be reviewed later.
    private func persistImportReport(_ report: ImportReport, actorID: UUID) {
        AppConfiguration.createDirectoriesIfNeeded()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd-HHmmss"
        let fname = "import-report-\(fmt.string(from: Date())).json"
        let url = AppConfiguration.exportsDirectory.appendingPathComponent(fname)
        var lines: [String] = [
            "{",
            "  \"imported\": \(report.imported),",
            "  \"rejected\": \(report.rejected),",
            "  \"actorID\": \"\(actorID)\",",
            "  \"errors\": ["
        ]
        for (i, e) in report.errors.enumerated() {
            let comma = i < report.errors.count - 1 ? "," : ""
            lines.append("    {\"row\":\(e.row),\"field\":\"\(e.field)\",\"reason\":\"\(e.reason)\",\"score\":\(e.score)}\(comma)")
        }
        lines.append("  ]")
        lines.append("}")
        let json = lines.joined(separator: "\n")
        try? json.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Per-row quality score (0–100). Weights per questions.md 5.1.
    func qualityScore(row: [String: String]) -> Int {
        let required = ["spuName", "barcode", "priceCents"]
        let presence = Int(Double(required.filter { row[$0]?.isEmpty == false }.count) /
                           Double(required.count) * 40.0)
        var format = 0
        if let price = Int64(row["priceCents"] ?? ""), price >= 0 { format += 20 }
        var options = 0
        if let wrap = row["wrapType"]?.lowercased(),
           ["", "paper", "burlap", "plastic", "ribbon"].contains(wrap) { options += 10 }
        var data = 0
        if let stem = Int(row["stemCount"] ?? ""), stem >= 0 { data += 10 }
        // Duplicates are handled separately, but reserve 20 points for it:
        let dupe = 20
        return presence + format + options + data + dupe
    }

    // MARK: - Export

    /// Writes a products CSV to `Documents/Exports/products-YYYYMMDD-HHMM.csv`,
    /// filtered by status and optionally masking sensitive fields (the
    /// description_ column is the demonstration case — most product fields
    /// aren't sensitive).
    @discardableResult
    func exportProductsCSV(statusFilter: ProductListingStatus?,
                           createdAfter: Date? = nil,
                           maskSensitive: Bool,
                           actorID: UUID) throws -> URL {
        let spus = try productRepo.fetchAllSPUs().filter { spu in
            let statusOK = statusFilter.map { spu.listingStatus == $0.rawValue } ?? true
            let dateOK   = createdAfter.map { spu.createdAt >= $0 } ?? true
            return statusOK && dateOK
        }
        let headers = ["spuName", "category", "listingStatus", "barcode",
                       "stemCount", "wrapType", "color", "priceCents", "isTaxable",
                       "description"]
        var rows: [[String: String]] = []
        for spu in spus {
            for sku in spu.skusArray {
                var desc = spu.description_ ?? ""
                if maskSensitive, !desc.isEmpty {
                    desc = MaskingHelper.maskLast(desc, showLast: 0)  // fully masked
                }
                rows.append([
                    "spuName": spu.name,
                    "category": spu.category ?? "",
                    "listingStatus": spu.listingStatus,
                    "barcode": sku.barcode,
                    "stemCount": "\(sku.stemCount)",
                    "wrapType": sku.wrapType ?? "",
                    "color": sku.color ?? "",
                    "priceCents": "\(sku.priceCents)",
                    "isTaxable": sku.isTaxable ? "true" : "false",
                    "description": desc,
                ])
            }
        }
        let csv = CSVParser.build(headers: headers, rows: rows)
        AppConfiguration.createDirectoriesIfNeeded()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd-HHmm"
        let fname = "products-\(fmt.string(from: Date())).csv"
        let url = AppConfiguration.exportsDirectory.appendingPathComponent(fname)
        try csv.data(using: .utf8)!.write(to: url, options: .atomic)

        AuditService.shared.logExport(actorID: actorID, masked: maskSensitive,
                                      context: context)
        try context.save()
        return url
    }
}

// MARK: - Helpers

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let s = self, !s.isEmpty else { return nil }
        return s
    }
}
