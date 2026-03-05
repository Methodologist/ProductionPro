# Production Pro

A cross-platform inventory management and production tracking app built with Flutter, designed for small-to-medium manufacturers and production teams. Provides real-time stock control, bill-of-materials production, team collaboration, sales analytics, and subscription billing — all backed by Firebase.

**Live Web App:** [https://inventory-r.web.app](https://inventory-r.web.app)

## Supported Platforms

| Platform | Status |
|----------|--------|
| Android  | ✅      |
| iOS      | ✅      |
| Windows  | ✅      |
| macOS    | ✅      |
| Web      | ✅      |

<img width="409" height="864" alt="image" src="https://github.com/user-attachments/assets/ed2571c3-876f-4fcd-8598-51ab1b564698" />
<img width="409" height="864" alt="image" src="https://github.com/user-attachments/assets/4c30d9b2-f50c-4cb4-bbc6-02fac795293b" />


## Features

### Authentication & Onboarding
- Email/password sign-up and sign-in with **email verification** required
- Two sign-up flows: **Create a new company** (Owner) or **Join an existing team** via 6-digit invite code
- Password reset, saved email for quick sign-in
- Rollback: if database setup fails after user creation, the Firebase Auth account is automatically deleted

### Multi-Organization Support
- Users can belong to multiple organizations
- Switch, create, join, rename, or leave organizations from the drawer menu
- Each organization has fully isolated data

### Role-Based Access Control

| Role           | Permissions                                      |
|----------------|--------------------------------------------------|
| Owner          | Full access — billing, team, reports, delete      |
| Business Admin | Manage stock, team, and settings                  |
| Manager        | Manage stock, assign tasks                        |
| Staff          | View stock, complete assigned tasks               |
| Inactive       | Deactivated — no access                           |

### Inventory / Stock Management
- Add, edit, archive, and delete stock items (components)
- Fields: name, quantity, min-stock threshold, cost per unit, barcode, image
- Color-coded stock level indicators (red / amber / green)
- Low stock alerts with badge count
- Barcode scanning via device camera
- Search and sort by name, quantity, or value
- Days-of-supply calculator based on last 30 days of sales

### Production / BOM Management
- Define products with a **Bill of Materials** (component → quantity mapping)
- **Produce** — run a batch, deduct raw materials, add finished goods to stock
- **Ship** — deduct finished goods, record a sale with revenue and profit
- **Undo Production** — reverse last batch
- Tiered product complexity (1–5) based on BOM nesting depth
- Per-product financials: cost, selling price, profit margin

### Task Delegation
- Assign tasks to team members with title, description, due date, and priority
- Color-coded priority indicators (High / Normal / Low)
- Mark complete/incomplete with notes
- Overdue visual indicators

### Purchase Orders
- Create purchase orders with supplier and line items linked to stock components
- **Receive Shipment** — bulk-add quantities to inventory
- Status tracking: Draft → Ordered → Received

### Audit Log
- Last 30 activity entries with actor, action, details, and timestamp
- Color-coded icons by action type (sale, stock, production, role change, etc.)

### CSV Import & Export
- **Import:** Pick a `.csv` file — auto-detects columns, upserts items by name
- **Export:** Sales data as CSV (date, product, qty, cost, price, revenue, profit, sold by)

### PDF Label Printing
- Generate printable PDF sheets of QR-code labels for any stock item
- Customizable label count, outputs to system print dialog

### Analytics & Reports (Pro)
- Time filters: Today, Week, Month, All
- KPIs: Total Revenue, Net Profit, Avg Margin %, Order Average
- Total Inventory Value (raw materials + finished goods)
- Revenue trend bar chart
- Top selling products with percentage bars
- Staff contribution breakdown
- CSV export

### Team Management
- View members and roles
- Invite users by email or 6-digit invite code
- Change roles, remove members
- Pending invite tracking

### Notifications
- Real-time notification bell with badge count
- Invitation and general notification streams

### Settings
- Edit display name
- View and manage organization memberships
- Dark mode toggle (persisted)

## Tier System

| Limit           | Free (Starter) | Pro         |
|-----------------|----------------|-------------|
| Stock Items     | 10             | 3,000       |
| Products        | 3              | 500         |
| Team Members    | 2              | 15          |
| Analytics       | Locked         | Unlocked    |
| Price           | Free           | $49.99/mo   |

A **7-day Pro trial** begins automatically when a company is created. Subscriptions are managed via RevenueCat (mobile app stores) or Stripe (direct billing).

## Tech Stack

**Framework:** Flutter (Dart), Material 3

**Firebase Services:**
- Firebase Auth — email/password with verification
- Cloud Firestore — named database instance (`east-5`)
- Firebase Hosting — web deployment
- Cloud Functions — Stripe checkout/webhooks, RevenueCat webhooks, billing portal

**Key Packages:**

| Package              | Purpose                        |
|----------------------|--------------------------------|
| `firebase_core`      | Firebase initialization        |
| `firebase_auth`      | Authentication                 |
| `cloud_firestore`    | Real-time database             |
| `cloud_functions`    | Server-side logic              |
| `flutter_stripe`     | Stripe payments (mobile)       |
| `purchases_flutter`  | RevenueCat subscriptions       |
| `mobile_scanner`     | Barcode / QR code scanning     |
| `csv`                | CSV import and export          |
| `pdf` + `printing`   | QR label PDF generation        |
| `file_picker`        | File selection for CSV import  |
| `share_plus`         | Share exported files           |
| `path_provider`      | Temp file storage              |
| `window_manager`     | Desktop window sizing          |
| `shared_preferences` | Persisted user preferences     |
| `image_picker`       | Image selection                |
| `url_launcher`       | External links                 |

## Getting Started

### Prerequisites
- Flutter SDK `>=3.3.0 <4.0.0`
- Firebase project with Auth, Firestore, Hosting, and Functions enabled
- A named Firestore database instance (`east-5`)

### Setup

1. **Clone the repository**
   ```bash
   git clone <repo-url>
   cd flutter_application_1
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   ```bash
   flutterfire configure
   ```
   Ensure `lib/firebase_options.dart` is generated with your project credentials.

4. **Run the app**
   ```bash
   # Android / iOS
   flutter run

   # Web
   flutter run -d chrome

   # Windows desktop
   flutter run -d windows
   ```

### Build & Deploy (Web)

```bash
flutter build web
firebase deploy --only hosting
```

### Deploy Cloud Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

## Project Structure

```
lib/
├── main.dart              # App entry point, all screens & business logic
├── firebase_options.dart   # FlutterFire CLI generated config
├── models.dart            # Data models (Component, Product, Sale, etc.)
├── user_model.dart        # User data model
├── pdf_service.dart       # QR-code label PDF generation
├── models/
│   └── component.dart     # Component model
└── widgets/
    └── auth_background.dart # Login screen gradient background

functions/
└── index.js               # Cloud Functions (Stripe, RevenueCat webhooks)

web/
└── index.html             # Web entry point (includes Stripe.js)
```

## Architecture Notes

- **`InventoryManager`** (`ChangeNotifier`) centralizes all business logic with real-time Firestore listeners
- **Dual subscription system:** RevenueCat for app stores + Stripe for direct billing, both converging on a single `isPro` flag per organization
- **Platform guards:** all native-only SDK calls (`dart:io`, Stripe, RevenueCat) are wrapped behind `kIsWeb` / `Platform` checks
- **Transaction-based team operations** prevent race conditions on membership changes
- **Portrait-only** orientation on mobile; fixed 400×850 window on desktop
