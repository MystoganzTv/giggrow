# GigGrow — iOS

Earnings, mileage and tax for drivers running more than one gig app.

Open `GigGrow.xcodeproj` in Xcode 16 or later and run. iOS 17+, SwiftUI and
SwiftData, portrait only. No account, no server of ours: data lives on the
device, and — if the driver is signed in to iCloud — syncs through CloudKit
into *their own* private database, which the developer cannot read.

## What it does

**Reads your earnings off a screenshot.** Uber and the rest have no public
API, so GigGrow takes the picture instead. On-device OCR pulls out the total,
tips, promotions, trips and hours, and — because a week of daily screens is
textually identical — reads *which* day by looking at which bar in the chart
is the solid one. You confirm every figure before it saves.

**Tracks miles.** Automatically via Core Location, or by hand with a
start/stop trip. Every drive is yours to mark business or personal, because
the IRS expects the classification to be the driver's and an app that guessed
would be handing you a number you can't defend.

**Estimates what you owe.** Federal, state and self-employment tax, worked out
after the mileage deduction and the QBI deduction come off — shown as
arithmetic rather than as a total you'd have to take on faith. For most
drivers the honest figure is well under the flat 25–30% they're told to hold
back.

## The one decision everything follows from

A `Shift` is a block of *time*, not a block of time on one app. Multi-app
drivers run Uber and DoorDash at once, so earnings hang off the shift
per-platform while the hours are stored once. Anything else double-counts
every overlapping hour and halves the headline rate.

## Layout

```
GigGrow/
├── GigGrowApp.swift              @main, one on-disk ModelContainer
├── RootView.swift                tab shell, snapshot cache, tracker owner
├── Model/
│   ├── Store/Entities.swift      @Model types — the persisted truth
│   ├── Store/SnapshotBuilder.swift  the projection every screen reads
│   ├── Models.swift              EarningsSnapshot, ranges, Money/Hours
│   ├── TaxEstimate.swift         dated IRS tables, worked estimate
│   ├── MileageRate.swift         the rate schedule, by date
│   ├── Import/                   OCR, the earnings parser, the day detector
│   ├── Tracking/                 Core Location + Core Motion mileage
│   └── Store/                    seeding, CSV export, provider seam
├── DesignSystem/                 GG.* tokens, glass cards, charts, tab bar
└── Screens/                      five tabs plus their sheets
```

## Tests

`⌘U`. 150-odd, weighted towards the arithmetic that ends up on a tax return:
bracket boundaries, the mid-year mileage rate change, metre-to-mile drift,
unclassified drives being worth nothing, and the parser preferring *your*
earnings over the customer's fare.

The UI has no tests. Every interaction bug so far was found by using the app.

## Design source

`Design/GigGrow.dc.html` is the original mockup the first five screens were
built from. It has since diverged — Apps became Taxes, the dashboard was
rebuilt around what needs doing rather than what happened — so treat it as
history, not as a spec.
