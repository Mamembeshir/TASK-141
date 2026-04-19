# GreenGate — Architecture & Design

## Architecture

```
┌─────────────────────┐
│   ViewControllers   │  UIKit, MVC. Storyboards for static, programmatic for dynamic.
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│      Services       │  Business logic, state machines, audit, optimistic locking.
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│    Repositories     │  Thin Core Data wrappers. Inject NSManagedObjectContext.
└──────────┬──────────┘
           │
┌──────────▼──────────┐
│     Core Data       │  NSPersistentContainer / SQLite in app sandbox.
└─────────────────────┘
```

Offline-first: no URLSession, no CloudKit, no remote dependencies. All data
in Core Data (SQLite-backed). Files on disk under Application Support.

## Core Data Model (high level)

```
User ──< AuditLog
User ──< createdSPUs ─> ProductSPU ──< ProductSKU ──< InventoryLot
                                        └──< OrderLineItem
User ──< Order ──< OrderLineItem ──> ProductSKU
         │
         └──< PaymentRecord

TicketEvent ──< ETicket ──< CheckInLog ──> User
Coupon ──> PriceRule
PropertyListing ──< PropertyChangeHistory ──> User
Attachment (parentType + parentID polymorphic FK)
```

## State Machines

### Product Listing (PRD 9.1)

```
DRAFT ──submit──▶ PENDING_APPROVAL ──approve──▶ LISTED
  ▲                   │                          │
  │                   └──reject(notes)───────────┘
  │                                              │
  │                                    ┌─────────┘
  │                                    ▼
  │                               PENDING_APPROVAL (delist)
  │                                    │
  │                                    ├──approve──▶ DELISTED ──edit──▶ DRAFT
  │                                    └──reject────▶ LISTED
```

### Order (PRD 9.2)

```
OPEN ──park──▶ PARKED ──unpark──▶ OPEN
 │                │ (30-min timer)
 │                └──auto-void──▶ VOIDED (inventory unreserved)
 │
 ├──complete──▶ COMPLETED ──return (≤30 d)──▶ RETURNED
 └──void─────▶ VOIDED
```

### Ticket (PRD 9.3)

```
VALID ──scan (valid window, unused)──▶ USED
  │
  ├──admin void──▶ VOIDED
  └──past doorCloseTime──▶ EXPIRED     (sweeper every 15 min)
```

### Property (PRD 9.4)

```
DRAFT ──submit──▶ IN_REVIEW ──approve──▶ PUBLISHED ──admin lock──▶ LOCKED
  ▲                   │                     │                        │
  │                   └──reject(notes)──────┤                        │
  │                                         │                        │
  └─────────────unpublish───────────────────┘◀──────admin unlock─────┘
```

### Event (PRD 9.5)

```
DRAFT ──publish──▶ ON_SALE ──soldCount == totalCapacity──▶ SOLD_OUT
                     │                                        │
                     └──admin close / past end──▶ CLOSED      │
                                                              │
                                           CLOSED ◀───────────┘
```

## POS Checkout Flow

1. `POSService.scanBarcode` resolves SKU (haptic success / error).
2. `addToCart` — reserves inventory on the SKU's primary lot.
3. `applyItemDiscount` / `applyOrderDiscount` — 30 % cap each
   (questions.md 1.2).
4. `applyCoupon` — validates dates + maxUses; records the rule as order
   discount.
5. `calculateTotals` — recomputes line totals, subtotal, order-discount,
   tax on taxable lines (banker's rounding), total.
6. `splitTender` — sum of PaymentRecords must equal `totalCents`.
7. `completeOrder` — OPEN → COMPLETED, decrement onHand, clear reservations,
   audit.

## Ticket Check-In Flow

```
QR bytes ──▶ AntiCounterfeitSigner.verify (HMAC-SHA256 over "num|event|from|to")
          │
          ├─ bad signature ──▶ log INVALID, haptic error
          │
          ├─ now < validFrom or now > validTo ──▶ log EXPIRED
          │
          ├─ ticket.status == USED ──▶ log DUPLICATE (show prior scanner + time)
          │
          └─ success ──▶ mark USED, event.checkedInCount++, log SUCCESS, haptic success
```

## Import Pipeline

```
CSV file (UIDocumentPickerViewController)
  ├─ CSVParser.parse (RFC 4180, quoted fields)
  ├─ per-row qualityScore (presence 40 + format 20 + options 10 + data 10 + dedup 20)
  ├─ rows < 70 ──▶ error report (partial success)
  ├─ valid rows ──▶ ProductService.createSPU/SKU (barcode-unique guard)
  └─ AuditService.logImport (imported, rejected counts)
```

## Attachment Pipeline

```
upload(sourceURL, declaredMime, parentType, parentID, licensing, copyright)
  ├─ MagicBytesValidator.validate (reject magic-byte mismatch)
  ├─ if image: ImageCompressor.compress (2048 px, JPEG 0.8)
  ├─ SHA256Helper.hash (hex) ─ dedup by (checksum, parent)
  ├─ write to Application Support/Attachments/{parentType}/{parentID}/{uuid}.{ext}
  ├─ ThumbnailGenerator (image → UIGraphicsImageRenderer; video → AVAssetImageGenerator)
  └─ persist Attachment row + audit
```

## Background Tasks (BGProcessingTask)

Registered in `AppDelegate.didFinishLaunchingWithOptions`:

- `OrphanCleanupTask` — daily; `CleanupService.cleanOrphans`.
- `EndOfDaySummaryTask` — daily; writes shift-close file.
- `ThumbnailGenerationTask` — hourly.
- `BulkImportTask` — triggered by user import.

Parked-ticket auto-expiry and ticket validity sweeps run on foreground
`Timer`s (5 min / 15 min respectively) — they need fast enough cadence that
background scheduling is the wrong primitive. Battery check: skipped when
device is below 20 % or in Low Power Mode (PERF-04).

## Cold-Start Strategy (PERF-01)

`DashboardViewController` issues lightweight aggregate fetches (`NSExpression`
`count:` descriptions) rather than loading full entity graphs. Detailed data
loads lazily when the user navigates.

## Memory Warnings (questions.md 6.2)

`AppDelegate.applicationDidReceiveMemoryWarning` posts
`Notification.Name.didReceiveMemoryWarning`. Views/services that hold image
caches register as observers and call `NSCache.removeAllObjects` /
purge in-memory decoded buffers. `NSCache` also evicts automatically under
system pressure.

## Role Gating

Enforced at the service layer (reviewer-only approvals, admin-only lock /
void), reinforced at the VC layer (workflow action sheets hide unavailable
options). Gate Attendants hit a specialised root in `SceneDelegate` that
exposes only `TicketScannerViewController` — no tab bar, no other modules.

## Optimistic Locking

Every entity carries `version: Int64`. Services read `version`, mutate, and
write `version + 1`. `CoreDataStack.checkAndIncrementVersion` provides a
shared helper; most services embed the check inline in their transition
routines.
