import BackgroundTasks
import CoreData

final class EndOfDaySummaryTask {

    static let identifier = "com.greengate.endofdaysummary"

    static func scheduleIfNeeded() {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = false

        // Schedule for 11:59 PM tonight
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 23
        components.minute = 59
        if let target = Calendar.current.date(from: components) {
            request.earliestBeginDate = target
        }
        try? BGTaskScheduler.shared.submit(request)
    }

    static func handle(task: BGProcessingTask) {
        scheduleIfNeeded()

        let context = CoreDataStack.shared.newBackgroundContext()

        task.expirationHandler = { task.setTaskCompleted(success: false) }

        context.perform {
            // Low-battery pause: skip heavy work and reschedule for tomorrow.
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled else {
                let req = BGProcessingTaskRequest(identifier: identifier)
                req.requiresNetworkConnectivity = false
                try? BGTaskScheduler.shared.submit(req)
                task.setTaskCompleted(success: true)
                return
            }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
                task.setTaskCompleted(success: false)
                return
            }

            let fetch = NSFetchRequest<Order>(entityName: "Order")
            fetch.predicate = NSPredicate(
                format: "createdAt >= %@ AND createdAt < %@ AND status == %@",
                today as NSDate, tomorrow as NSDate, OrderStatus.completed.rawValue
            )

            guard let orders = try? context.fetch(fetch) else {
                task.setTaskCompleted(success: false)
                return
            }

            let totalSales = orders.reduce(Int64(0)) { $0 + $1.totalCents }
            let orderCount = orders.count

            let returnFetch = NSFetchRequest<Order>(entityName: "Order")
            returnFetch.predicate = NSPredicate(
                format: "createdAt >= %@ AND createdAt < %@ AND status == %@",
                today as NSDate, tomorrow as NSDate, OrderStatus.returned.rawValue
            )
            let returns = (try? context.fetch(returnFetch)) ?? []
            let totalReturns = returns.reduce(Int64(0)) { $0 + $1.totalCents }

            let summary = buildSummaryCSV(
                date: today,
                orderCount: orderCount,
                totalSalesCents: totalSales,
                returnCount: returns.count,
                totalReturnsCents: totalReturns
            )

            let fileName = "EOD_Summary_\(ISO8601DateFormatter().string(from: today)).csv"
            let outputURL = AppConfiguration.exportsDirectory.appendingPathComponent(fileName)
            try? summary.write(to: outputURL, atomically: true, encoding: .utf8)

            task.setTaskCompleted(success: true)
        }
    }

    private static func buildSummaryCSV(
        date: Date,
        orderCount: Int,
        totalSalesCents: Int64,
        returnCount: Int,
        totalReturnsCents: Int64
    ) -> String {
        let dateStr = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
        var lines = ["Date,Metric,Value"]
        lines.append("\(dateStr),Orders Completed,\(orderCount)")
        lines.append("\(dateStr),Total Sales,\(CurrencyFormatter.string(fromCents: totalSalesCents))")
        lines.append("\(dateStr),Returns,\(returnCount)")
        lines.append("\(dateStr),Total Returns,\(CurrencyFormatter.string(fromCents: totalReturnsCents))")
        lines.append("\(dateStr),Net Revenue,\(CurrencyFormatter.string(fromCents: totalSalesCents + totalReturnsCents))")
        return lines.joined(separator: "\n")
    }
}
