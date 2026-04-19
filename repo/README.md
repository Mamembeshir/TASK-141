# GreenGate

A fully offline iOS Operations Suite for an independent venue/retail
operator — floral product management, POS checkout, e-ticketing with
anti-counterfeit QR codes, and rentable-property listings. All data lives
on-device; there is no server, no network API, and no cloud dependency.

## Architecture & Tech Stack

* **Platform:** iOS 17+ (iPhone and iPad, Split View supported)
* **UI Framework:** UIKit (no SwiftUI) with Auto Layout + Dynamic Type
* **Persistence:** Core Data over SQLite (`NSPersistentContainer`)
* **Auth:** Keychain-backed password hashes + `LocalAuthentication` (FaceID / TouchID)
* **Barcode / QR:** `AVFoundation` (scanning) + Core Image `CIQRCodeGenerator` (generation)
* **Crypto:** `CryptoKit` HMAC-SHA256 (ticket anti-counterfeit signing)
* **Background Work:** `BackgroundTasks` framework (`BGProcessingTask`)
* **Testing:** XCTest (unit / integration / view layers)
* **Package Manager:** Swift Package Manager (no CocoaPods, no Carthage)
* **Containerization:** Not applicable — this is a native iOS app. The
  equivalent "reproducible environment" is the Xcode toolchain + iOS
  Simulator, both of which are pinned in the Prerequisites section below.

## Project Structure

```text
.
├── GreenGate/                      # App source
│   ├── App/                        # AppDelegate, SceneDelegate, AppConfiguration
│   ├── Models/
│   │   ├── CoreData/               # .xcdatamodeld + NSManagedObject subclasses
│   │   ├── Enums.swift
│   │   └── Errors.swift
│   ├── Database/                   # CoreDataStack, Seeder
│   ├── Repositories/               # Thin Core Data wrappers (one per domain)
│   ├── Services/                   # Business logic (ProductService, POSService, …)
│   ├── ViewControllers/            # UIKit screens grouped by module
│   ├── BackgroundTasks/            # BGProcessingTask handlers
│   ├── Utilities/                  # Crypto, formatters, imaging, CSV, masking
│   └── Resources/                  # Assets.xcassets, LaunchScreen.storyboard
├── GreenGateTests/
│   ├── UnitTests/                  # Service / utility tests (in-memory)
│   ├── IntegrationTests/           # Services × in-memory Core Data
│   └── ViewTests/                  # ViewController rendering tests
├── GreenGate.xcodeproj/            # Xcode project
├── Makefile                        # make build / make test / make clean
├── run_tests.sh                    # Standardized test runner - MANDATORY
└── README.md                       # Project documentation - MANDATORY
```


## Prerequisites

* **macOS** Ventura (13) or later
* **Xcode** 15.0 or later
* **iOS 17+ Simulator** (iPhone 16 Pro is the default test destination;
  any iOS 17+ iPhone or iPad simulator works)

No Docker, no Node, no Python, no backend services. The app runs entirely
on the local Apple toolchain.

## Running the Application

1. **Open the project in Xcode:**
   ```bash
   open GreenGate.xcodeproj
   ```

2. **Select a simulator and run:**
   Pick an iPhone or iPad simulator from the scheme selector and press
   **⌘R**. First launch seeds demo accounts and fixture data automatically.

3. **Build from the command line (optional):**
   ```bash
   make build
   ```
   or explicitly:
   ```bash
   xcodebuild -scheme GreenGate \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   ```

4. **Stop the application:** stop the active run in Xcode (**⌘.**) or quit
   the simulator.

## Testing

All unit, integration, and view tests are executed via a single
standardized script. It orchestrates the iOS Simulator automatically and
exits with code `0` on success / non-zero on failure so it drops straight
into any CI/CD validator.

```bash
chmod +x run_tests.sh
./run_tests.sh
```

Run a single layer:

```bash
./run_tests.sh --unit
./run_tests.sh --integration
./run_tests.sh --views
```

Or via `make`:

```bash
make test              # all three layers
make test-unit
make test-integration
make test-views
```

## Seeded Credentials

On first launch the app seeds a default admin account. In **Debug builds
only** (`#if DEBUG`), additional role accounts and sample data are also
seeded for development and testing purposes. These extra accounts are
**not present in Release/TestFlight builds**.

| Role                | Username    | Password     | Build       | Notes |
| :------------------ | :---------- | :----------- | :---------- | :---- |
| **Admin**           | `admin`     | `GreenGate1` | All builds  | Full access; only role that can lock properties or void tickets. |
| **Cashier**         | `cashier1`  | `Cashier01`  | Debug only  | POS only; cannot approve product listings. |
| **Gate Attendant**  | `gate1`     | `GateGuard1` | Debug only  | Sees only the ticket scanner — no tabs, no other modules. |
| **Content Manager** | `content1`  | `Content01`  | Debug only  | Creates/edits products and properties; cannot approve. |
| **Reviewer**        | `reviewer1` | `Reviewer01` | Debug only  | Approves or rejects listing and property submissions. |
