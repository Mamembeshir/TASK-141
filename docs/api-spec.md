# GreenGate — Internal API Contracts

This document describes the internal contracts between layers: Core Data
entities, repositories, services, and view controllers. There is no network
API — every "contract" here is a Swift interface within the app.

Layer boundaries:

```
ViewControllers  →  Services  →  Repositories  →  Core Data
```

Business logic lives in Services. Repositories are a thin, testable wrapper
around `NSFetchRequest` / inserts. View Controllers never call Core Data
directly.

## Core Data Entities

All entities carry `id: UUID`, `version: Int64` (optimistic lock), and —
where applicable — `createdAt`/`updatedAt` timestamps. Money is stored as
`Int64` cents. Relationships use Cascade or Nullify delete rules as noted in
`GreenGate.xcdatamodel`.

| Entity                    | Notes |
|---------------------------|-------|
| User                      | Local auth. `role`, `status`, `failedLoginCount`, `lockedUntil`. |
| ProductSPU                | Standard Product Unit. `listingStatus`, `pendingDelist`, `rejectionNotes`, `reviewerID`, `reviewedAt`, `lowStockThreshold`. |
| ProductSKU                | Variant. Unique `barcode`, `priceCents`, `isTaxable`. |
| InventoryLot              | `onHand`, `reservedCount`, `lotDate`. `available = onHand - reservedCount`. |
| PriceRule                 | `discountType`, `discountValue`, `maxDiscountPercent`. |
| Coupon                    | `code`, `validFrom`/`validTo`, `maxUses`/`currentUses`. |
| Order                     | `orderNumber` (GG-YYYYMMDD-NNNN), `status`, `subtotalCents`/`discountCents`/`taxCents`/`totalCents`, `orderDiscountPercent`, `couponCode`, `originalOrderNumber`. |
| OrderLineItem             | `quantity`, `unitPriceCents`, `discountCents`, `lineTotalCents`. |
| PaymentRecord             | `tenderType`, `amountCents`, `referenceMemo`. |
| TicketEvent               | `doorOpenTime`/`doorCloseTime`, `totalCapacity`, `soldCount`, `checkedInCount`, `status`. |
| ETicket                   | `ticketNumber`, `qrPayload`, `antiCounterfeitSignature`, `status`, `validFrom`/`validTo`. |
| CheckInLog                | `scannedAt`, `result` (SUCCESS/DUPLICATE/INVALID/EXPIRED), `scannedBy`. |
| PropertyListing           | US address, `rentCents`, `depositCents`, `leaseTermMonths`, `availableFrom`, `status`, `amenities` (JSON). |
| PropertyChangeHistory     | One row per field change: `fieldName`, `oldValue`, `newValue`, `changedBy`, `changedAt`. |
| Attachment                | `parentType`/`parentID`, `filePath`, `checksumSHA256`, `thumbnailPath`, `isCompressed`, `licensingInfo`/`copyrightInfo`. |
| AuditLog                  | Append-only. `actorID`, `action`, `entityType`, `entityID`, `beforeJSON`/`afterJSON`, `timestamp`. |

## Repositories

Each repository is injected with an `NSManagedObjectContext` so tests can
run against an in-memory store.

| Repository             | Responsibility |
|------------------------|----------------|
| `ProductRepository`    | SPU/SKU fetches + inserts, barcode uniqueness check. |
| `InventoryRepository`  | Primary-lot resolution, low-stock query. |
| `CouponRepository`     | Fetch by id/code. |
| `OrderRepository`      | Fetch by id/number, parked list, completed-in-range, daily order count. |
| `TicketRepository`     | Event + ticket fetches/inserts, check-in logs, valid-tickets-past-`now`. |
| `PropertyRepository`   | Fetch/insert listings, insert change-history rows. |
| `AttachmentRepository` | Fetch by parent, dedup by checksum. |

## Services

| Service                | Highlights |
|------------------------|------------|
| `AuthService`          | `register`, `login` (5-strike lockout), `logout`, `biometricAuth`, `setStatus`. |
| `ProductService`       | `createSPU`, `createSKU` (barcode uniqueness), listing state machine (`submitForApproval` / `approve` / `reject` / `requestDelist` / `approveDelist`). |
| `InventoryService`     | `adjustStock`, `reserveStock`, `unreserveStock`, `getAvailable`, `checkLowStock(threshold:)`. |
| `POSService`           | `scanBarcode`, `addToCart`, `applyItemDiscount` / `applyOrderDiscount` (30 % cap), `applyCoupon`, `calculateTotals`, `splitTender`, `parkOrder` / `unparkOrder` / `completeOrder` / `voidOrder`, `processReturn` (30-day window), `generateOrderNumber`. |
| `ParkedTicketService`  | `checkExpired`; auto-voids orders parked > 30 min and unreserves inventory. 5-minute timer. |
| `ShiftCloseService`    | `closeShift` → end-of-day summary text file in Documents/Exports/. |
| `TicketService`        | `createEvent`, `publishEvent`, `generateTicket` (HMAC signed, capacity sold-out), `checkIn` (SUCCESS/DUPLICATE/EXPIRED/INVALID), `voidTicket` (Admin). |
| `TicketExpiryService`  | `checkExpired` every 15 min; VALID past `doorCloseTime` → EXPIRED. |
| `PropertyService`      | `create`, `update` (per-field change history), state machine (`submitForReview`, `approve`, `reject`, `lock`, `unlock`, `unpublish`). |
| `AttachmentService`    | `upload` — magic-bytes validation → image compression → SHA-256 dedup → thumbnail. |
| `CleanupService`       | `cleanOrphans` — delete files > 7 days old with no Core Data reference. |
| `ImportExportService`  | `importProductsCSV` (quality score ≥ 70, partial success), `exportProductsCSV` (status filter, mask toggle). |
| `AuditService`         | `logCreate` / `logUpdate` / `logApprove` / `logReject` / `logVoid` / `logReturn` / `logCheckIn` / `logImport` / `logExport` / `logShiftClose`. |

## View Controllers

Each module has a list + detail + form (+ specialised screens). All list
views use `NSFetchedResultsController` for automatic diffing. All forms
delegate writes to their Service and surface errors via `UIAlertController`.

| Domain      | VCs |
|-------------|-----|
| Auth        | `LoginViewController` |
| Dashboard   | `DashboardViewController` |
| Products    | `ProductListViewController`, `ProductDetailViewController`, `ProductFormViewController`, `InventoryViewController` |
| POS         | `POSViewController`, `CartViewController`, `CheckoutViewController`, `ParkedTicketsViewController`, `ReturnExchangeViewController` |
| Tickets     | `EventListViewController`, `EventDetailViewController`, `TicketScannerViewController`, `TicketDetailViewController` |
| Properties  | `PropertyListViewController`, `PropertyDetailViewController`, `PropertyFormViewController`, `ChangeHistoryViewController` |
| Admin       | `UserManagementViewController`, `AuditLogViewController`, `ImportExportViewController` |

## Role Gating (enforced in services)

- **Reviewer**-only: `ProductService.approve/reject`, `PropertyService.approve/reject`.
- **Admin**-only: `PropertyService.lock/unlock`, `TicketService.voidTicket`.
- **Gate Attendant**: the `SceneDelegate` returns a scanner-only root when
  the logged-in user has `role == GATE_ATTENDANT`.

## State Machines

See `docs/design.md` for the full diagrams. PRD references:
- Product listing — PRD 9.1 (DRAFT / PENDING_APPROVAL / LISTED / DELISTED)
- Order — PRD 9.2 (OPEN / PARKED / COMPLETED / RETURNED / VOIDED)
- Ticket — PRD 9.3 (VALID / USED / VOIDED / EXPIRED)
- Property — PRD 9.4 (DRAFT / IN_REVIEW / PUBLISHED / LOCKED)
- Event — PRD 9.5 (DRAFT / ON_SALE / SOLD_OUT / CLOSED / CANCELLED)
