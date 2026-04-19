import CoreData
import Foundation

/// Background sweeper that transitions VALID tickets past their event's
/// doorCloseTime to EXPIRED (PRD 9.3). Polls every 15 minutes by default.
final class TicketExpiryService {

    static let shared = TicketExpiryService(context: CoreDataStack.shared.viewContext)

    private let context: NSManagedObjectContext
    private let repo: TicketRepository
    private var timer: Timer?

    init(context: NSManagedObjectContext) {
        self.context = context
        self.repo = TicketRepository(context: context)
    }

    func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            try? self?.checkExpired()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @discardableResult
    func checkExpired(now: Date = Date()) throws -> [ETicket] {
        let due = try repo.fetchValidTicketsPast(now)
        for t in due {
            t.status = TicketStatus.expired.rawValue
            t.version += 1
        }
        if !due.isEmpty { try context.save() }
        return due
    }
}
