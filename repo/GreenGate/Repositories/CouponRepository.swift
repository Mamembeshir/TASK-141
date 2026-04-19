import CoreData
import Foundation

final class CouponRepository {

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetch(id: UUID) throws -> Coupon? {
        let r = NSFetchRequest<Coupon>(entityName: "Coupon")
        r.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetch(code: String) throws -> Coupon? {
        let r = NSFetchRequest<Coupon>(entityName: "Coupon")
        r.predicate = NSPredicate(format: "code ==[c] %@", code)
        r.fetchLimit = 1
        return try context.fetch(r).first
    }

    func fetchAll() throws -> [Coupon] {
        let r = NSFetchRequest<Coupon>(entityName: "Coupon")
        r.sortDescriptors = [NSSortDescriptor(key: "code", ascending: true)]
        return try context.fetch(r)
    }
}
