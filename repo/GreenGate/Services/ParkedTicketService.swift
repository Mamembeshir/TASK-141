import CoreData
import Foundation

/// Background sweeper for parked orders. POS-09: any PARKED order older than
/// `AppConfiguration.parkedOrderExpiryMinutes` (default 30) is VOIDED and
/// inventory is unreserved.
final class ParkedTicketService {

    static let shared = ParkedTicketService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let orders: OrderRepository
    private let pos: POSService
    private var timer: Timer?

    init(context: NSManagedObjectContext, pos: POSService? = nil) {
        self.context = context
        self.orders = OrderRepository(context: context)
        self.pos = pos ?? POSService(context: context)
    }

    // MARK: - Scheduler

    /// Starts a 5-minute timer that calls `checkExpired` on every tick.
    func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            try? self?.checkExpired()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Core sweep

    /// Returns the orders that were auto-voided during this sweep.
    @discardableResult
    func checkExpired(now: Date = Date(), actorID: UUID = UUID()) throws -> [Order] {
        let parked = try orders.fetchParked()
        let windowSec = TimeInterval(AppConfiguration.parkedOrderExpiryMinutes * 60)
        var expired: [Order] = []
        for order in parked {
            guard let parkedAt = order.parkedAt else { continue }
            if now.timeIntervalSince(parkedAt) >= windowSec {
                try pos.voidOrder(orderID: order.id, actorID: actorID)
                expired.append(order)
            }
        }
        return expired
    }
}
