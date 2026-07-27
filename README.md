# GigGrow — iOS

SwiftUI implementation of `Design/GigGrow.dc.html`. Five screens, dark, mock data.

Open `GigGrow.xcodeproj` in Xcode 16 or later and run. iOS 17+, portrait only.

## Layout

```
GigGrow/
├── GigGrowApp.swift            @main
├── RootView.swift               tab shell — hosts the five screens
├── Model/
│   ├── Models.swift             Platform, ServiceItem, SettingGroup, Vehicle,
│   │                            EarningsSnapshot + Money/Num formatters
│   └── MockData.swift           the design's DCLogic values, ported verbatim,
│                                plus the chart series as SVG-space coordinates
├── DesignSystem/
│   ├── Theme.swift              colours, gradients, radii, type ramp, RadialWash
│   ├── Glass.swift              GlassCard, HeroCard, StatTile, Pill, ProgressBar,
│   │                            SplitBar, DonutRings, Chevron
│   ├── Charts.swift             SeriesLine/Area/Curve, BarChart, Sparkline, AxisLabels
│   ├── Icons.swift              the five tab glyphs, traced from the design's SVG
│   ├── Logo.swift               vector rebuild of the brand mark
│   ├── GGTabBar.swift           custom translucent tab bar
│   └── ScreenScaffold.swift     shared screen chrome
└── Screens/
    ├── DashboardView.swift      01
    ├── AppsView.swift           02
    ├── AnalyticsView.swift      03
    ├── VehicleView.swift        04
    └── SettingsView.swift       05
```

The Xcode target uses a file-system-synchronized group, so new files under
`GigGrow/` join the build automatically — no `project.pbxproj` edits.

## How the design was carried across

**Colours and type.** Every value in `Theme.swift` maps to a literal in the
design doc. The design's variable font weights (680, 660, 540 …) are mapped to
the nearest system weight, and each `letter-spacing` em value is precomputed as
a `tracking` point value on the matching style.

**Charts.** The design hard-codes its charts as SVG path data. Those coordinates
live in `ChartData` in their original viewBox space, and the shapes in
`Charts.swift` rescale them to whatever frame they're given — so the curves are
identical to the design at any width, on any device.

**Numbers.** Nothing is hard-coded as a string. `EarningsSnapshot` holds the
inputs and derives the rest exactly as the design's `renderVals()` did — tax and
maintenance set-asides, per-platform amounts, bar widths normalised against the
top platform, the maintenance percentage. All eleven rendered strings were
checked against the design output and match byte for byte.

**Brand mark.** The app icon is derived from the supplied artwork: the mark was
alpha-keyed off its plate and recomposited onto a violet bloom at 1024×1024
(`Assets.xcassets/AppIcon.appiconset`). For in-app use it's also rebuilt as
vector geometry in `Logo.swift` — the gauge arc, six graduation ticks, three
ascending bars and the needle breaking out as an arrow — so it stays sharp at
20pt. It appears in the Settings footer; `GigGrowIconTile` is available if you
want it elsewhere.

## Deliberate deviations

| | Design | Here | Why |
|---|---|---|---|
| Status bar | Mock "9:41" drawn into each frame | Real system status bar | It's an app, not a mockup |
| Screen size | Fixed 393 × 852 | Safe-area relative | Adapts to every iPhone |
| Tab bar | Static, drawn per frame | One `GGTabBar`, real selection | Tabs actually switch |
| Service rows | Divider under every row | No divider after the last | Divider met the card edge |
| Analytics range | "Week" always selected | Working segmented control | Charts are static for now |
| Logo | Absent from the screens | Settings footer | Additive; disturbs no designed row |

## Data layer

SwiftData, `Model/Store/`. Entities are in `Entities.swift`, the projection in
`SnapshotBuilder.swift`, first-run contents in `Seed.swift`.

**A shift is a block of time, not a block of time on one app.** Multi-app
drivers run Uber and DoorDash simultaneously, so `Shift` stores the hours once
and `PlatformEarning` hangs each app's take off it. The alternative — one shift
per platform — double-counts every overlapping hour and halves the headline
$/hour, which is the number the whole product rests on.

**Per-platform hours are attributed, not measured.** With two apps on at once
there's no ground truth for "hours on Uber", so a shift's hours are split in
proportion to what each app paid. The attributed hours therefore sum to hours
actually worked. The split is over *online* hours rather than active ones, so
per-app rates share a denominator with the headline and can be compared to it.

**The five screens didn't change.** `EarningsSnapshot` was always a projection;
it's now computed from the store instead of holding literals. `.mock` survives
as preview data so every `#Preview` still works offline.

A fresh install seeds a profile, the six platforms, a service schedule and a
demo week whose totals reproduce the design exactly — $1,482.60 across
38.4 online hours, 9.2 idle, 612 miles, 214 units of work, split
29/21/18/14/11/7%. Five of its seven days run two or three apps at once, so the
attribution logic is exercised from first launch.

## Charts

`ChartSeries` carries plain arrays; the shapes normalise them at draw time, so
no pixel coordinates survive outside the design doc.

A shift's gross is spread across the two-hour buckets it actually spans — a
15:00–21:30 block feeds the 14:00, 16:00, 18:00 and 20:00 slots rather than
dumping everything at its start time. The buckets sum back to the week's gross
exactly. They begin at 06:00 rather than midnight, which puts the five axis
labels on bucket boundaries instead of between them.

"Peak 6–8pm" is computed from the busiest bucket. Hard-coded, as the design had
it, the caption could contradict the bars directly beneath it.

The monthly curve falls back to the design's series until two months of history
exist, since a new account has nothing to plot.

## Pricing

`Model/Subscription.swift` holds every price; none is typed into a view.

Pro is **$9.99/month or $79.99/year**. That was set against the market, not
picked: Gridwise Plus is $14.99/mo or $107.99/yr, Solo runs $8–$15/mo billed
annually, Stride is free. The design's original $20/mo sat above every
competitor for a smaller product.

**Sync is not the paid feature, and shouldn't be.** Gridwise and Solo both buy
automatic earnings sync from the same class of aggregator, so it's the price of
entry rather than a reason to subscribe. The paywall leads with the maintenance
reserve, which neither competitor offers — they treat the car as a mileage
number, not as an asset that needs a repair budget.

Free keeps manual entry, the dashboard, analytics and the tax set-aside.
Pro adds the reserve, true cost per mile, sync and export.

Free users see the maintenance card with the figure they *would* have banked,
rather than an empty locked box. A wedge nobody can see isn't a wedge.

## Providers

`EarningsProvider` is the seam between where shifts come from and everything
that reads them. `ManualEarningsProvider` ships today;
`AggregatorEarningsProvider` is a deliberate stub, because connecting one costs
money per account per month and that's a commercial decision before it's a
technical one.

The note in that file worth keeping: an aggregator returns per-gig rows, and
mapping each one to its own `Shift` would reintroduce exactly the
double-counted hours this data model exists to avoid. Overlapping windows have
to be merged.

## Ranges

`AnalyticsRange` owns three things that have to agree: the window of time, how
that window is cut into bars, and which prior period a delta compares against.
Keeping them on one type is what stops a month view from quietly comparing
itself to last week.

A month is cut into weeks rather than days — 31 bars are unreadable at phone
width, and drivers think about a month in weeks. Verified against a synthetic
year: every range's buckets sum back to that range's gross, with no shift
falling between buckets.

RootView builds **two** projections: the week for four screens, and the
selected range for Analytics. Sharing one mutable range would mean tapping a
pill on Analytics silently switched the dashboard to yearly figures.

## Not yet built

No networking, no platform OAuth. Expenses have a model and feed the
projection, but no entry UI.

Nothing here has been run against real driver data, only against the seeded
week. The parsing paths that would replace manual entry — statement CSVs,
weekly summary emails — don't exist yet.
