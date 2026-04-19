import CoreData

/// Runs once on first launch. Seeds the admin account and any debug fixtures.
final class Seeder {

    private static let seededKey = "GreenGate.didSeedInitialData"

    static func seedIfNeeded(context: NSManagedObjectContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        context.perform {
            do {
                try seedAdminUser(in: context)
                #if DEBUG
                try seedDebugFixtures(in: context)
                #endif
                try context.save()
                UserDefaults.standard.set(true, forKey: seededKey)
            } catch {
                context.rollback()
                print("⚠️ Seeder failed: \(error)")
            }
        }
    }

    // MARK: - Admin User

    private static func seedAdminUser(in context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<User>(entityName: "User")
        fetch.predicate = NSPredicate(format: "username == %@", "admin")
        let existing = try context.fetch(fetch)
        guard existing.isEmpty else { return }

        let admin = User(context: context)
        admin.id = UUID()
        admin.username = "admin"
        admin.role = Role.admin.rawValue
        admin.status = UserStatus.active.rawValue
        admin.failedLoginCount = 0
        admin.biometricEnabled = false
        admin.version = 0
        admin.createdAt = Date()

        // Store password hash in Keychain
        KeychainHelper.shared.storePasswordHash(
            for: admin.id.uuidString,
            password: "GreenGate1"
        )
    }

    // MARK: - Debug Fixtures

    #if DEBUG
    private static func seedDebugFixtures(in context: NSManagedObjectContext) throws {
        try seedSupportUsers(in: context)
        try seedSampleProducts(in: context)
        try seedSampleEvent(in: context)
        try seedSampleProperty(in: context)
    }

    private static func seedSupportUsers(in context: NSManagedObjectContext) throws {
        let usersToSeed: [(String, Role, String)] = [
            ("cashier1",  .cashier,        "Cashier01"),
            ("gate1",     .gateAttendant,  "GateGuard1"),
            ("content1",  .contentManager, "Content01"),
            ("reviewer1", .reviewer,       "Reviewer01"),
        ]

        for (username, role, password) in usersToSeed {
            let fetch = NSFetchRequest<User>(entityName: "User")
            fetch.predicate = NSPredicate(format: "username == %@", username)
            let existing = try context.fetch(fetch)
            guard existing.isEmpty else { continue }

            let user = User(context: context)
            user.id = UUID()
            user.username = username
            user.role = role.rawValue
            user.status = UserStatus.active.rawValue
            user.failedLoginCount = 0
            user.biometricEnabled = false
            user.version = 0
            user.createdAt = Date()

            KeychainHelper.shared.storePasswordHash(for: user.id.uuidString, password: password)
        }
    }

    private static func seedSampleProducts(in context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<ProductSPU>(entityName: "ProductSPU")
        fetch.fetchLimit = 1
        let existing = try context.fetch(fetch)
        guard existing.isEmpty else { return }

        let spu = ProductSPU(context: context)
        spu.id = UUID()
        spu.name = "Spring Bouquet"
        spu.description_ = "A fresh, seasonal arrangement of mixed spring flowers."
        spu.category = "Bouquets"
        spu.isListed = true
        spu.listingStatus = ProductListingStatus.listed.rawValue
        spu.version = 0
        spu.createdAt = Date()

        let sku1 = ProductSKU(context: context)
        sku1.id = UUID()
        sku1.barcode = "GG-SPRING-12PK"
        sku1.stemCount = 12
        sku1.wrapType = "Paper"
        sku1.color = "Pink"
        sku1.priceCents = 2500
        sku1.isTaxable = true
        sku1.isActive = true
        sku1.version = 0
        sku1.spu = spu

        let lot1 = InventoryLot(context: context)
        lot1.id = UUID()
        lot1.onHand = 50
        lot1.reservedCount = 0
        lot1.lotDate = Date()
        lot1.version = 0
        lot1.sku = sku1

        let sku2 = ProductSKU(context: context)
        sku2.id = UUID()
        sku2.barcode = "GG-SPRING-24PK"
        sku2.stemCount = 24
        sku2.wrapType = "Burlap"
        sku2.color = "Mixed"
        sku2.priceCents = 4500
        sku2.isTaxable = true
        sku2.isActive = true
        sku2.version = 0
        sku2.spu = spu

        let lot2 = InventoryLot(context: context)
        lot2.id = UUID()
        lot2.onHand = 8
        lot2.reservedCount = 0
        lot2.lotDate = Date()
        lot2.version = 0
        lot2.sku = sku2
    }

    private static func seedSampleEvent(in context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<TicketEvent>(entityName: "TicketEvent")
        fetch.fetchLimit = 1
        let existing = try context.fetch(fetch)
        guard existing.isEmpty else { return }

        let cal = Calendar.current
        let eventDate = cal.date(byAdding: .day, value: 30, to: Date())!
        let openTime  = cal.date(bySettingHour: 18, minute: 0, second: 0, of: eventDate)!
        let closeTime = cal.date(bySettingHour: 22, minute: 0, second: 0, of: eventDate)!

        let event = TicketEvent(context: context)
        event.id = UUID()
        event.name = "GreenGate Spring Gala"
        event.venue = "The Garden Pavilion"
        event.eventDate = eventDate
        event.doorOpenTime = openTime
        event.doorCloseTime = closeTime
        event.totalCapacity = 200
        event.soldCount = 0
        event.checkedInCount = 0
        event.status = EventStatus.onSale.rawValue
        event.version = 0
    }

    private static func seedSampleProperty(in context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<PropertyListing>(entityName: "PropertyListing")
        fetch.fetchLimit = 1
        let existing = try context.fetch(fetch)
        guard existing.isEmpty else { return }

        let availableFrom = Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        let listing = PropertyListing(context: context)
        listing.id = UUID()
        listing.title = "Garden Event Space — Downtown"
        listing.addressLine1 = "100 Bloom Street"
        listing.addressLine2 = "Suite 200"
        listing.city = "New York"
        listing.state = "NY"
        listing.zipCode = "10001"
        listing.squareFootage = 2500
        listing.amenities = "[\"WiFi\",\"Parking\",\"Kitchen\",\"AV Equipment\"]"
        listing.rentCents = 350000
        listing.depositCents = 700000
        listing.leaseTermMonths = 12
        listing.availableFrom = availableFrom
        listing.status = PropertyStatus.published.rawValue
        listing.version = 0
        listing.createdAt = Date()
    }
    #endif
}
