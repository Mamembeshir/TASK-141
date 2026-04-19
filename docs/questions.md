# GreenGate — Business Logic Questions Log

---

## 1. POS & Payments

### 1.1 How does "card-on-file placeholder" work without online processing?
* **Question:** The prompt says PaymentRecord supports "cash + card-on-file placeholder without online processing." What does the card-on-file record represent?
* **My Understanding:** This is a memo entry. The actual card charge happens on an external terminal (outside the app). The app records that a card payment was made so the order totals balance.
* **Solution:** PaymentRecord with tenderType = CARD_ON_FILE stores an `amountCents` and a `referenceMemo` (e.g., "Visa ending 4242, terminal ref #1234"). No actual card processing occurs in the app. The record exists solely for bookkeeping so that the sum of all PaymentRecords equals the Order.totalCents.

### 1.2 How does the 30% discount cap work when both per-item and order-level discounts are applied?
* **Question:** The prompt says "per-item and order-level discounts capped at 30%." Is that 30% each, or 30% combined?
* **My Understanding:** The 30% cap applies independently: no single line item's discount can exceed 30% of its price, and the order-level discount cannot exceed 30% of the subtotal. However, the combined effect could theoretically exceed 30% total if both are applied.
* **Solution:** Per-item discount: max 30% of that item's unit price × quantity. Order-level discount: max 30% of pre-discount subtotal. These are validated independently. If someone needs a combined cap, that's a future enhancement (documented here). The POS UI shows the effective discount percentage and warns if approaching the cap.

### 1.3 What happens to inventory when an order is parked?
* **Question:** Parked tickets hold items in the cart. Is the inventory reserved during parking?
* **My Understanding:** Yes — if a customer is mid-checkout, those items shouldn't be sold to someone else. But the reservation must expire when the parked ticket expires.
* **Solution:** When an order is parked: `InventoryLot.reservedCount` incremented for each line item's SKU. When unparked: reservation stays (it was already reserved when added to cart). When parked ticket auto-expires (30 min): order VOIDED, `reservedCount` decremented, items back to available. Available = `onHand - reservedCount`.

### 1.4 How is the return/exchange process structured?
* **Question:** The prompt says "returns/exchanges that require original-order lookup and block refunds past 30 days." What's the exact flow?
* **My Understanding:** The cashier looks up the original order by order number, selects items to return, and the system creates a new "return order" with negative amounts.
* **Solution:** Return flow: (1) Cashier enters original order number. (2) System fetches the completed order. If > 30 days ago → block with error "Return period expired." (3) Cashier selects line items and quantities to return. (4) System creates a new Order with status = RETURNED, negative lineTotalCents for each returned item. (5) Inventory restored: `onHand` incremented for returned quantities. (6) Refund PaymentRecord created (negative amountCents, same tender type as original or cash). The original order's status changes to RETURNED.

### 1.5 How is the order number generated?
* **Question:** The prompt doesn't specify the format.
* **My Understanding:** Standard retail format: prefix + date + sequential number.
* **Solution:** Format: `GG-{YYYYMMDD}-{4-digit sequential}`. Example: GG-20260415-0001. Sequential number resets daily. Managed via a counter in UserDefaults or a dedicated Core Data entity (OrderCounter with date + lastNumber).

---

## 2. E-Ticketing

### 2.1 How is the anti-counterfeit signature generated and verified?
* **Question:** The prompt says "anti-counterfeit signatures" for tickets but doesn't specify the algorithm.
* **My Understanding:** HMAC-SHA256 is standard for offline signature verification. The signing key is stored locally in Keychain.
* **Solution:** Signing: `HMAC-SHA256(ticketNumber + "|" + eventID + "|" + validFrom_ISO + "|" + validTo_ISO, secretKey)`. The secret key is generated on first launch and stored in Keychain. QR payload contains: `ticketNumber|eventID|validFrom|validTo|signature`. Verification: scanner reads QR, splits fields, recomputes HMAC, compares to the embedded signature. If match: valid. If mismatch: counterfeit.

### 2.2 What does the check-in duplicate blocking actually show?
* **Question:** The prompt says "blocks duplicate validations while logging who scanned and when." What does the scanner see?
* **My Understanding:** On duplicate, the scanner shows the original check-in details so the gate attendant knows it's a reuse, not a system error.
* **Solution:** Duplicate scan response: "⚠️ Already Checked In — Scanned by [gate attendant name] at [time]." This is displayed on-screen with a red highlight and error haptic. The CheckInLog records the duplicate attempt as well (result = DUPLICATE) for audit purposes.

### 2.3 How does the validity window work across time zones?
* **Question:** The prompt gives an example "03/27/2026 6:00 PM–10:00 PM." Is this local time?
* **My Understanding:** Event times are local to the venue. Since this is a single-venue app with no server, all times are in the device's local timezone.
* **Solution:** `validFrom` and `validTo` on ETicket are stored as `Date` (UTC internally) but displayed and input in the device's local timezone. The check-in comparison uses the device's current time against validFrom/validTo. Since all devices at the venue share the same timezone, this works. If a device's clock is wrong, the check-in will be wrong — but that's an operational issue, not a software issue.

---

## 3. Products & Inventory

### 3.1 What's the relationship between SPU and SKU?
* **Question:** The prompt uses "SPU-SKU specs (stem count, wrap type, color)." How are these structured?
* **My Understanding:** SPU = the abstract product (e.g., "Spring Bouquet"). SKU = a specific purchasable variant defined by its attributes (e.g., 12 stems, paper wrap, pink). One SPU has many SKUs.
* **Solution:** ProductSPU holds shared info: name, description, category. ProductSKU holds variant-specific info: barcode, stemCount, wrapType, color, price, taxability. The POS scans a barcode which resolves to a specific SKU. The product detail screen shows the SPU with all its SKU variants.

### 3.2 How does the listing/delisting approval flow work?
* **Question:** The prompt says "listing/delisting approval." Who initiates and who approves?
* **My Understanding:** Content Manager creates/edits products and requests listing. Reviewer approves or rejects. Same for delisting.
* **Solution:** Content Manager sets listing status → PENDING_APPROVAL. Reviewer sees the request in their review queue. Reviewer approves → LISTED (product appears in POS barcode lookup). Reviewer rejects → DRAFT with rejection notes. For delisting: Content Manager requests delist → PENDING_APPROVAL → Reviewer approves → DELISTED (hidden from POS). This prevents products from being arbitrarily listed/delisted without oversight.

---

## 4. Properties

### 4.1 What does "Locked" status mean for a property?
* **Question:** The status workflow has LOCKED as the final state. What does locking do?
* **My Understanding:** Locked means the listing is frozen — no edits allowed. This is used when a lease is signed or the property is under contract. Only Admin can unlock.
* **Solution:** LOCKED status: no edits to any field. Content Manager cannot modify. Admin can unlock (→ PUBLISHED) if needed (e.g., lease falls through). The lock is for data integrity during active leases. The change history continues to record the lock/unlock actions.

### 4.2 How detailed is the change history?
* **Question:** The prompt says "auditable change history visible to Admin/Reviewer." Is this per-field or per-save?
* **My Understanding:** Per-field is more useful for auditing. If someone changes the rent and the square footage in the same save, both changes should be individually recorded.
* **Solution:** `PropertyChangeHistory` records one row per changed field per save. Each row: listing_id, changedBy, fieldName (e.g., "rentCents"), oldValue, newValue, changedAt. On save, the service diffs all fields against the fetched state and inserts a history row for each changed field. The UI shows a timeline of changes grouped by save timestamp, with individual field diffs visible when expanded.

---

## 5. Import/Export

### 5.1 How does the quality score work?
* **Question:** The prompt says "quality score thresholds like minimum 70/100." How is the score calculated?
* **My Understanding:** A weighted checklist that evaluates each row for completeness and correctness.
* **Solution:** Per-row quality score (0–100) computed as: required fields present (40 points) + format validation passed (20 points) + no duplicates detected (20 points) + option values valid (10 points — e.g., wrap type in allowed list) + price/quantity reasonable (10 points — e.g., price > 0, quantity ≥ 0). Rows scoring < 70 are rejected. The error report shows each row's score breakdown.

### 5.2 What does "partial success" mean for imports?
* **Question:** Can valid rows be imported even if some rows fail?
* **My Understanding:** Yes — the import processes all rows, imports the valid ones, skips the invalid ones, and produces a summary.
* **Solution:** Import is NOT atomic (not all-or-nothing). Each row is processed independently. Valid rows (score ≥ 70, no duplicates, all validations pass) are imported into Core Data. Invalid rows are collected into an error report. Transaction summary: "Imported: X rows. Rejected: Y rows. Duplicates: Z rows." The user reviews the error report and can fix and re-import the rejected rows.

### 5.3 How does field masking work in exports?
* **Question:** The prompt says exports can "optionally mask sensitive fields (e.g., renter phone shown as ***-***-1234)."
* **My Understanding:** The export function has a toggle for masking. When enabled, it applies masking rules to designated sensitive fields.
* **Solution:** `MaskingHelper` has rules per field: phone → "***-***-{last 4}", email → "***@{domain}", SSN → "***-**-{last 4}". The export UI has a "Mask sensitive fields" toggle (default ON). When enabled, the CSV/Excel output uses masked values. When OFF (Admin only), raw values are exported. The export audit log records whether masking was applied.

---

## 6. Performance

### 6.1 How do we achieve cold start under 1.5 seconds?
* **Question:** Core Data with a large dataset could be slow to initialize.
* **My Understanding:** The key is to NOT fetch all data at launch. Only fetch what's needed for the first screen (dashboard counts).
* **Solution:** On launch: (1) Core Data stack initializes with `NSPersistentContainer.loadPersistentStores` (fast — just opens the SQLite file). (2) Dashboard VC requests only aggregate counts via lightweight Core Data fetch requests (`NSExpression` with `count:`): total products, open orders, today's events, active listings. (3) Detailed data is loaded lazily when the user navigates to a specific section. (4) NSFetchedResultsController is set up per-screen, not globally. This keeps launch to under 1.5 seconds even with 10,000+ records.

### 6.2 How does memory warning handling work?
* **Question:** The prompt says "clear image caches" on memory warning.
* **My Understanding:** Use NSCache for all image caches (thumbnails, full-size) so they auto-evict. Additionally, explicitly purge on didReceiveMemoryWarning.
* **Solution:** All image caches use `NSCache` (auto-evicts under memory pressure). Additionally, `AppDelegate.applicationDidReceiveMemoryWarning` posts a notification. All VCs and services that hold image data listen and explicitly clear: thumbnail caches, decompressed image buffers, any in-memory attachment previews. Core Data faulting also helps — fetched objects that aren't being displayed can be faulted to free memory.