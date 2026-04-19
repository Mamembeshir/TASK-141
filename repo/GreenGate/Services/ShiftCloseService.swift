import CoreData
import Foundation

/// End-of-day shift summary (POS-12). Aggregates completed/returned orders in
/// the given day and writes a human-readable text file to the app sandbox.
final class ShiftCloseService {

    static let shared = ShiftCloseService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let orders: OrderRepository

    init(context: NSManagedObjectContext) {
        self.context = context
        self.orders = OrderRepository(context: context)
    }

    struct Summary: Equatable {
        let day: Date
        let cashierID: UUID
        let salesCents: Int64
        let returnsCents: Int64
        let netSalesCents: Int64
        let byTender: [String: Int64]
        let orderCount: Int
        let returnCount: Int
    }

    /// Computes the summary, writes it to disk, and records an audit entry.
    /// Returns the summary and the output file URL.
    @discardableResult
    func closeShift(cashierID: UUID, day: Date = Date()) throws -> (Summary, URL) {
        let summary = try buildSummary(cashierID: cashierID, day: day)
        let url = try writeSummary(summary)
        AuditService.shared.logShiftClose(
            actorID: cashierID,
            totalSalesCents: summary.netSalesCents,
            context: context
        )
        try context.save()
        return (summary, url)
    }

    // MARK: - Summary construction

    func buildSummary(cashierID: UUID, day: Date) throws -> Summary {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
        let completed = try orders.fetchCompleted(in: start...end)

        var sales: Int64 = 0
        var returns: Int64 = 0
        var byTender: [String: Int64] = [:]
        var orderCount = 0
        var returnCount = 0

        for o in completed {
            switch o.status {
            case OrderStatus.completed.rawValue:
                sales += o.totalCents
                orderCount += 1
                for p in o.paymentsArray {
                    byTender[p.tenderType, default: 0] += p.amountCents
                }
            case OrderStatus.returned.rawValue where o.originalOrderNumber != nil:
                returns += o.totalCents  // totalCents is negative
                returnCount += 1
                for p in o.paymentsArray {
                    byTender[p.tenderType, default: 0] += p.amountCents
                }
            default:
                break
            }
        }
        return Summary(
            day: start,
            cashierID: cashierID,
            salesCents: sales,
            returnsCents: returns,
            netSalesCents: sales + returns,
            byTender: byTender,
            orderCount: orderCount,
            returnCount: returnCount
        )
    }

    // MARK: - File output

    /// Writes the summary as plain text into Documents/Exports/.
    func writeSummary(_ s: Summary) throws -> URL {
        AppConfiguration.createDirectoriesIfNeeded()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyyMMdd"
        let name = "shift-close-\(fmt.string(from: s.day)).txt"
        let url = AppConfiguration.exportsDirectory.appendingPathComponent(name)

        var lines: [String] = []
        lines.append("GreenGate Shift Close — \(fmt.string(from: s.day))")
        lines.append("Cashier: \(s.cashierID.uuidString)")
        lines.append("Orders: \(s.orderCount)   Returns: \(s.returnCount)")
        lines.append("Sales:    \(CurrencyFormatter.string(fromCents: s.salesCents))")
        lines.append("Returns:  \(CurrencyFormatter.string(fromCents: s.returnsCents))")
        lines.append("Net:      \(CurrencyFormatter.string(fromCents: s.netSalesCents))")
        lines.append("")
        lines.append("By tender:")
        for (k, v) in s.byTender.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(k): \(CurrencyFormatter.string(fromCents: v))")
        }
        let content = lines.joined(separator: "\n") + "\n"
        try content.data(using: .utf8)!.write(to: url, options: .atomic)
        return url
    }
}
