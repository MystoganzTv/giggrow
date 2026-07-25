# GigPilot — iOS

SwiftUI implementation of `Design/GigPilot.dc.html`. Five screens, dark, mock data.

Open `GigPilot.xcodeproj` in Xcode 16 or later and run. iOS 17+, portrait only.

## Layout

```
GigPilot/
├── GigPilotApp.swift            @main
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
│   ├── GPTabBar.swift           custom translucent tab bar
│   └── ScreenScaffold.swift     shared screen chrome
└── Screens/
    ├── DashboardView.swift      01
    ├── AppsView.swift           02
    ├── AnalyticsView.swift      03
    ├── VehicleView.swift        04
    └── SettingsView.swift       05
```

The Xcode target uses a file-system-synchronized group, so new files under
`GigPilot/` join the build automatically — no `project.pbxproj` edits.

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
20pt. It appears in the Settings footer; `GigPilotIconTile` is available if you
want it elsewhere.

## Deliberate deviations

| | Design | Here | Why |
|---|---|---|---|
| Status bar | Mock "9:41" drawn into each frame | Real system status bar | It's an app, not a mockup |
| Screen size | Fixed 393 × 852 | Safe-area relative | Adapts to every iPhone |
| Tab bar | Static, drawn per frame | One `GPTabBar`, real selection | Tabs actually switch |
| Service rows | Divider under every row | No divider after the last | Divider met the card edge |
| Analytics range | "Week" always selected | Working segmented control | Charts are static for now |
| Logo | Absent from the screens | Settings footer | Additive; disturbs no designed row |

## Not yet built

Mock data only — no networking, persistence, or platform OAuth. The
Week/Month/Year control animates and holds state but doesn't re-slice the
charts. Every button is inert except tab selection and the range picker.

`EarningsSnapshot` is the single seam: swap `.mock` in `RootView` for a live
source and all five screens follow.
