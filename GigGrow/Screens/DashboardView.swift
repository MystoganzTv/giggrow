//
//  DashboardView.swift
//  GigGrow
//
//  Screen 01 — the week at a glance.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    let snapshot: EarningsSnapshot
    @Binding var scope: DashboardScope
    @Binding var anchor: Date
    /// The dashboard was hard-wired to the current week. Nothing about "at a
    /// glance" requires that it can only ever be *this* glance.
    var onLogShift: () -> Void = {}
    var onShowHistory: () -> Void = {}
    var onImport: () -> Void = {}
    var onShowMileage: () -> Void = {}
    var onShowExpenses: () -> Void = {}
    var onAddExpense: () -> Void = {}

    @Query private var drives: [DriveRecord]
    @Query(sort: \Shift.start, order: .reverse) private var allShifts: [Shift]
    @Query private var profiles: [DriverProfile]
    @Environment(\.ggUsesWideLayout) private var usesWideLayout
    @Namespace private var scopeAnimation
    @State private var isPickingDashboardPeriod = false
    @State private var chartMode: DashboardChartMode = .cumulative

    var body: some View {
        ScreenScaffold(maxContentWidth: dashboardContentMaxWidth) {
            GG.Gradients.dashboardWash()
        } content: {
            header

            // Keep the overview and Week / Year / Total selector visible even
            // when the selected period is empty. Hiding the entire card used
            // to trap someone on an empty week despite years of saved work.
            if usesTabletLayout {
                tabletDashboard
            } else {
                phoneDashboard
            }
        }
        .sheet(isPresented: $isPickingDashboardPeriod) {
            PeriodPickerView(selection: dashboardRangeSelection)
        }
    }

    /// Regular-width iPads get a dashboard composition rather than a widened
    /// phone feed. Compact windows (including Split View) fall back to the
    /// single column automatically.
    private var usesTabletLayout: Bool { usesWideLayout }

    private var dashboardContentMaxWidth: CGFloat {
        usesTabletLayout
            ? GG.Layout.tabletContentMaxWidth
            : GG.Layout.contentMaxWidth
    }

    private var phoneDashboard: some View {
        VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
            heroCard
            if snapshot.hasData {
                keepCard
                if !attention.isEmpty { attentionCard }
                setAsideTiles
                earningsByApp
                rateTiles
                hoursCard
                expensesCard
            } else {
                emptyState
            }
        }
    }

    /// The left side is an earnings workspace: overview, recent days and app
    /// mix. The right rail answers what is safe to keep and what needs action.
    private var tabletDashboard: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                heroCard
                if snapshot.hasData {
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if snapshot.hasData {
                VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
                    keepCard
                    if !attention.isEmpty { attentionCard }
                    setAsideTiles
                    rateTiles
                    hoursCard
                    expensesCard
                    earningsByApp
                }
                .frame(minWidth: 310, idealWidth: 350, maxWidth: 380,
                       alignment: .topLeading)
            }
        }
    }

    // MARK: What's actually yours

    /// The number nobody else shows: what's left after both set-asides.
    ///
    /// It was spread across three tiles the driver had to subtract in their
    /// head — gross here, tax there, maintenance somewhere else. "I made
    /// \(Money.whole(snapshot.weeklyTotal))" is the number that gets spent;
    /// this is the one that's safe to.
    private var keepCard: some View {
        GlassCard {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Yours to keep")
                    Text(Money.cents(keepable))
                        .ggText(.system(size: 30, weight: .bold), tracking: -1,
                                color: GG.Palette.mint)
                    Text("After \(Int(snapshot.taxRate))% tax and \(Int(snapshot.maintenanceRate))% maintenance")
                        .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var keepable: Double {
        let held = (snapshot.taxRate + snapshot.maintenanceRate) / 100
        return max(snapshot.weeklyTotal * (1 - held), 0)
    }

    // MARK: What needs you

    /// Work waiting on a decision, not figures.
    ///
    /// This is the difference between a dashboard and a report. A report says
    /// what happened; a dashboard says what to do about it. Unclassified
    /// drives are worth nothing until sorted, and nothing else in the app was
    /// going to tell you they were sitting there.
    private var attentionCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("Needs you")
                    .ggText(GG.Typo.cardTitle, tracking: GG.Typo.cardTitleTracking)
                    .padding(.bottom, 4)

                ForEach(Array(attention.enumerated()), id: \.offset) { index, item in
                    Button(action: item.action) {
                        HStack(alignment: .top, spacing: 11) {
                            Circle().fill(item.tint)
                                .frame(width: 6, height: 6).padding(.top, 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .ggText(.system(size: 14, weight: .semibold))
                                Text(item.detail)
                                    .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Chevron(size: 14, color: Color.white.opacity(0.25))
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < attention.count - 1 {
                        RowDivider(color: GG.Surface.dividerSoft)
                    }
                }
            }
        }
    }

    private var unsortedDrives: Int {
        drives.filter { $0.purpose == .unclassified }.count
    }

    /// What sorting them would actually be worth. "12 drives to sort" is a
    /// chore; "$47 in deductions" is a reason.
    private var unsortedValue: Double {
        let override = profiles.first?.mileageRate ?? 0
        return drives
            .filter { $0.purpose == .unclassified }
            .reduce(0) { total, drive in
                let rate = override > 0 ? override : MileageRates.rate(on: drive.start)
                return total + drive.miles * rate
            }
    }

    /// A shift with no hours is invisible to every rate in the app.
    private var shiftsMissingHours: Int {
        allShifts.filter { $0.hours <= 0 && $0.gross > 0 }.count
    }

    private struct AttentionItem {
        let title: String
        let detail: String
        let tint: Color
        let action: () -> Void
    }

    private var attention: [AttentionItem] {
        var items: [AttentionItem] = []

        if unsortedDrives > 0 {
            items.append(AttentionItem(
                title: "\(unsortedDrives) drive\(unsortedDrives == 1 ? "" : "s") to sort",
                detail: "Worth \(Money.cents(unsortedValue)) in deductions once you say which were for work.",
                tint: GG.Palette.amber,
                action: onShowMileage
            ))
        }

        if shiftsMissingHours > 0 {
            items.append(AttentionItem(
                title: "\(shiftsMissingHours) shift\(shiftsMissingHours == 1 ? "" : "s") without hours",
                detail: "Your hourly rate leaves these out until they have a time.",
                tint: GG.Palette.amber,
                action: onShowHistory
            ))
        }

        return items
    }

    // MARK: Expenses

    /// Expenses, on the screen people actually open.
    ///
    /// They were reachable only from a menu behind a button labelled "Log",
    /// which hid the whole feature: a driver who wanted to record a tank of
    /// fuel had to guess that "Log" also meant "spend". Worse, the menu is
    /// hidden on Settings and on an empty dashboard, so the one place a new
    /// driver looks had no route to it at all.
    ///
    /// Deliberately last on the dashboard. Expenses matter at tax time, not
    /// at the end of a shift — but they have to be visible to be remembered
    /// at all, and a receipt is only worth logging on the day you got it.
    private var expensesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Expenses")
                        .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)
                    Spacer(minLength: 8)
                    Button(action: onShowExpenses) {
                        Text("All")
                            .ggText(.system(size: 13, weight: .medium),
                                    color: GG.Palette.violet300)
                    }
                    .buttonStyle(.plain)
                }

                Text("Fuel, tolls, a phone mount, a brake job. Photograph the receipt and GigGrow reads the amount — and keeps the picture, which is the part the IRS asks for.")
                    .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onAddExpense) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Add an expense")
                            .font(.system(size: 14.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(GG.Gradients.segment, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: GG.Layout.stackSpacing) {
            // The screenshot is the fast path, so it gets the primary button.
            // Typing eight figures in is the fallback, not the headline.
            // "No shifts yet this week" is true and useless when you have
            // just imported June and it's July: it reads as the import having
            // failed. Say which it is.
            if !allShifts.isEmpty {
                Button(action: onShowHistory) {
                    GlassCard(radius: GG.Radius.tile,
                              padding: EdgeInsets(top: 16, leading: 18,
                                                  bottom: 16, trailing: 18)) {
                        HStack(alignment: .top, spacing: 11) {
                            Circle().fill(GG.Palette.violet400)
                                .frame(width: 6, height: 6).padding(.top, 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(emptyHistoryTitle)
                                    .ggText(.system(size: 13.5, weight: .semibold))
                                Text("Your earlier records are still saved. Use Total on the earnings card or tap here to inspect them.")
                                    .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Chevron(size: 15, color: Color.white.opacity(0.28))
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            EmptyStateCard(
                title: emptyTitle,
                message: "Screenshot your gig app's earnings screen and GigGrow reads the figures off it. Faster than typing, and you're not transcribing numbers by hand.",
                actionTitle: "Import a screenshot",
                action: onImport,
                showsLogo: true
            )

            Button(action: onLogShift) {
                HStack(spacing: 9) {
                    Text("Or enter a shift by hand")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GG.Palette.violet300)
                    Spacer(minLength: 0)
                    Chevron(size: 15, color: GG.Palette.violet300.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(GG.Palette.violet500.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: GG.Radius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GG.Radius.tile, style: .continuous)
                        .strokeBorder(GG.Palette.violet400.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // The set-asides are the reason to bother, so name them up front
            // rather than showing two tiles reading $0.
            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What happens after you log")
                        .ggText(GG.Typo.rowTitle, tracking: GG.Typo.rowTitleTracking)

                    explainerRow(
                        "\(Int(snapshot.taxRate))% held for taxes",
                        "Nothing owed in April that you haven't already put away."
                    )
                    RowDivider()
                    explainerRow(
                        "\(Int(snapshot.maintenanceRate))% held for the car",
                        "The next repair is paid for before it happens."
                    )
                    RowDivider()
                    explainerRow(
                        "Real hourly rate",
                        "Hours counted once, even with three apps running at the same time."
                    )
                }
            }
        }
    }

    private var emptyTitle: String {
        switch scope {
        case .week:    return "No shifts yet this week"
        case .year:    return "No shifts yet this year"
        case .allTime: return "No earnings logged yet"
        }
    }

    private var emptyHistoryTitle: String {
        switch scope {
        case .week:    return "Nothing this week, but you have earlier shifts"
        case .year:    return "Nothing this year, but you have earlier shifts"
        case .allTime: return "Your records need attention"
        }
    }

    private func explainerRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .ggText(GG.Typo.rowLabel)
            Text(detail)
                .ggText(GG.Typo.footnote, color: GG.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    // MARK: Header

    /// Names the driver rather than the period. A dashboard is the one screen
    /// that should feel like it belongs to someone.
    private var greeting: String {
        let hour = Calendar.gigGrow.component(.hour, from: .now)
        let name = snapshot.driver.name.split(separator: " ").first.map(String.init) ?? ""
        let part = hour < 12 ? "Morning" : (hour < 18 ? "Afternoon" : "Evening")
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var header: some View {
        // Profile and Settings now have a permanent tab. Earnings History
        // lives inside Settings, so the dashboard header can simply identify
        // whose business is being shown instead of repeating navigation.
        Text(greeting)
            .ggText(GG.Typo.screenTitle, tracking: GG.Typo.screenTitleTracking)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Hero

    private var heroCard: some View {
        HeroCard(glow: true) {
            VStack(alignment: .leading, spacing: 0) {
                scopePicker

                periodNavigator
                    .padding(.top, 15)

                HStack(alignment: .bottom, spacing: 10) {
                    Text(Money.cents(snapshot.weeklyTotal))
                        .ggText(GG.Typo.heroAmount, tracking: GG.Typo.heroAmountTracking)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .contentTransition(.numericText())

                    if let comparison = scope.comparisonLabel,
                       snapshot.weeklyChange != "—" {
                        VStack(alignment: .leading, spacing: 2) {
                            Pill(
                                text: trendMagnitude,
                                foreground: trendColor,
                                background: trendBackground,
                                font: .system(size: 13, weight: .semibold),
                                horizontalPadding: 9,
                                showsTrendArrow: true,
                                trendIsNegative: trendIsNegative
                            )
                            Text(comparison)
                                .ggText(.system(size: 10.5, weight: .medium),
                                        color: Color.white.opacity(0.38))
                                .padding(.leading, 4)
                        }
                        .padding(.bottom, 4)
                    }
                }
                .padding(.top, 8)

                VStack(spacing: 9) {
                    HStack(spacing: 8) {
                        Text(chartMode.title(for: scope))
                            .ggText(.system(size: 10.5, weight: .semibold),
                                    tracking: 0.2,
                                    color: Color.white.opacity(0.44))
                        Spacer(minLength: 0)
                        Text("Tap to switch")
                            .ggText(.system(size: 9.5, weight: .medium),
                                    color: Color.white.opacity(0.28))
                    }

                    Group {
                        if chartMode == .cumulative {
                            HeroAreaChart(
                                points: heroCumulative
                                    .chartPoints(box: ChartData.weekTrendBox),
                                box: ChartData.weekTrendBox
                            )
                        } else {
                            BarChart(
                                bars: heroBarValues,
                                maxHeight: max(
                                    CGFloat(heroBuckets.max() ?? 0),
                                    1
                                ),
                                height: 72,
                                cornerRadius: 6,
                                spacing: scope == .year ? 5 : 9
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            chartMode.toggle()
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(chartMode.accessibilityLabel(for: scope))
                    .accessibilityHint("Double tap to change chart style")
                    .accessibilityAddTraits(.isButton)

                    AxisLabels(labels: heroLabels, color: Color.white.opacity(0.42))
                }
                .padding(.top, 18)

                HStack(spacing: 0) {
                    heroStat("Online", Hours.clock(snapshot.onlineHours))
                    heroStat(completedMetricLabel, Num.grouped(snapshot.tripCount))
                    heroStat("Per hour", snapshot.perHourLabel)
                    heroStat("Miles", snapshot.mileage > 0
                             ? Num.grouped(snapshot.mileage)
                             : "—")
                }
                .padding(.top, 18)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: scope)
        .animation(.easeInOut(duration: 0.28), value: anchor)
    }

    private var periodNavigator: some View {
        HStack(spacing: 10) {
            if scope != .allTime {
                periodArrow(-1, systemName: "chevron.left", enabled: true)
            }

            Button {
                guard scope != .allTime else { return }
                isPickingDashboardPeriod = true
            } label: {
                VStack(alignment: scope == .allTime ? .leading : .center,
                       spacing: 2) {
                    HStack(spacing: 5) {
                        Text(scopePeriodTitle.uppercased())
                            .ggText(GG.Typo.heroEyebrow,
                                    tracking: GG.Typo.heroEyebrowTracking,
                                    color: Color.white.opacity(0.60))
                        if scope != .allTime {
                            Chevron(size: 10, color: Color.white.opacity(0.35))
                                .rotationEffect(.degrees(90))
                        }
                    }
                    if !dashboardPeriodIsCurrent && scope != .allTime {
                        Text("Tap to choose another \(scope == .week ? "week" : "year")")
                            .ggText(.system(size: 9.5, weight: .medium),
                                    color: GG.Palette.violet300.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity,
                       alignment: scope == .allTime ? .leading : .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(scope == .allTime)

            Text("\(historyDays.count) earning \(historyDays.count == 1 ? "day" : "days")")
                .ggText(GG.Typo.captionMuted,
                        color: Color.white.opacity(0.38))
                .fixedSize()

            if scope != .allTime {
                periodArrow(
                    1,
                    systemName: "chevron.right",
                    enabled: !dashboardPeriodIsCurrent
                )
            }
        }
    }

    private func periodArrow(
        _ delta: Int,
        systemName: String,
        enabled: Bool
    ) -> some View {
        Button {
            let component: Calendar.Component = scope == .week
                ? .weekOfYear
                : .year
            if let moved = Calendar.gigGrow.date(
                byAdding: component,
                value: delta,
                to: anchor
            ) {
                anchor = moved
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled
                                 ? Color.white.opacity(0.62)
                                 : Color.white.opacity(0.18))
                .frame(width: 30, height: 30)
                .background(Color.black.opacity(enabled ? 0.20 : 0.08),
                            in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            "\(delta < 0 ? "Previous" : "Next") \(scope == .week ? "week" : "year")"
        )
    }

    private var dashboardRangeSelection: Binding<RangeSelection> {
        Binding {
            RangeSelection(
                range: scope == .year ? .year : .week,
                anchor: anchor
            )
        } set: { selection in
            anchor = selection.anchor
        }
    }

    private var dashboardPeriodIsCurrent: Bool {
        guard scope != .allTime else { return true }
        let dates = allShifts.map(\.start)
        return scope.window(recordDates: dates, now: anchor)
            == scope.window(recordDates: dates, now: .now)
    }

    private var scopePicker: some View {
        HStack(spacing: 3) {
            ForEach(DashboardScope.allCases) { option in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        scope = option
                    }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 11.5,
                                      weight: option == scope ? .semibold : .medium))
                        .foregroundStyle(option == scope
                                         ? Color.white
                                         : Color.white.opacity(0.46))
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .background {
                            if option == scope {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                GG.Palette.violet400.opacity(0.95),
                                                GG.Palette.blue400.opacity(0.82)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .matchedGeometryEffect(
                                        id: "dashboard-scope",
                                        in: scopeAnimation
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Show \(option.activityLabel) earnings")
                .accessibilityAddTraits(option == scope ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.20), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func heroStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .ggText(.system(size: 8.5, weight: .semibold),
                        tracking: 0.8,
                        color: Color.white.opacity(0.36))
                .lineLimit(1)
            Text(value)
                .ggText(.system(size: 13.5, weight: .semibold),
                        tracking: -0.2,
                        color: Color.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scopePeriodTitle: String {
        switch scope {
        case .week:
            let window = dashboardWindow
            let end = window.upperBound.addingTimeInterval(-1)
            let startFormatter = DateFormatter()
            startFormatter.dateFormat = "MMM d"
            let endFormatter = DateFormatter()
            endFormatter.dateFormat = Calendar.gigGrow.isDate(
                window.lowerBound,
                equalTo: end,
                toGranularity: .month
            ) ? "d" : "MMM d"
            return "\(startFormatter.string(from: window.lowerBound))–\(endFormatter.string(from: end))"
        case .year:
            return String(Calendar.gigGrow.component(.year, from: anchor))
        case .allTime:
            return "All recorded earnings"
        }
    }

    /// The platform already knows what its completed work is called. Showing
    /// "Completed 214" made the number look unfinished; a Lyft-only period
    /// should say Rides, Uber should say Trips, and a mixed period should use
    /// the honest umbrella term Jobs.
    private var completedMetricLabel: String {
        let nouns = Set(
            historyShifts
                .flatMap(\.earningItems)
                .filter { $0.trips > 0 }
                .map { $0.account?.unitNoun.lowercased() ?? "jobs" }
        )
        guard nouns.count == 1, let noun = nouns.first else { return "Jobs" }
        return noun.capitalized
    }

    private var trendIsNegative: Bool {
        snapshot.weeklyChange.trimmingCharacters(in: .whitespaces)
            .hasPrefix("-")
    }

    private var trendMagnitude: String {
        snapshot.weeklyChange
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private var trendColor: Color {
        trendIsNegative ? Color(hex: 0xFB7185) : GG.Palette.mint
    }

    private var trendBackground: Color {
        trendIsNegative
            ? Color(hex: 0xFB7185, opacity: 0.16)
            : Color(hex: 0x34D399, opacity: 0.16)
    }

    private var heroCumulative: [Double] {
        var running = 0.0
        return heroBuckets.map {
            running += $0
            return running
        }
    }

    private var heroBarValues: [(height: CGFloat, opacity: Double)] {
        heroBuckets.map { value in
            (
                height: CGFloat(max(value, 0)),
                opacity: value > 0 ? 0.92 : 0.18
            )
        }
    }

    private var heroBuckets: [Double] {
        guard scope == .allTime else { return snapshot.series.primary }

        let groups = allTimeYearGroups
        guard groups.count > 1 else { return snapshot.series.primary }

        return groups.map { group in
            allShifts
                .filter {
                    group.years.contains(
                        Calendar.gigGrow.component(.year, from: $0.start)
                    )
                }
                .reduce(0) { $0 + $1.gross }
        }
    }

    private var heroLabels: [String] {
        switch scope {
        case .week:
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE d"
            return (0..<7).compactMap { offset in
                Calendar.gigGrow.date(
                    byAdding: .day,
                    value: offset,
                    to: dashboardWindow.lowerBound
                )
            }
            .map { formatter.string(from: $0) }

        case .year:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM"
            let start = dashboardWindow.lowerBound
            return (0..<12).compactMap { offset in
                Calendar.gigGrow.date(
                    byAdding: .month,
                    value: offset,
                    to: start
                )
            }
            .map { formatter.string(from: $0) }

        case .allTime:
            break
        }

        let groups = allTimeYearGroups
        guard groups.count > 1 else { return snapshot.series.primaryLabels }
        return groups.map(\.label)
    }

    private var yearsWithEarnings: [Int] {
        Array(Set(allShifts.map {
            Calendar.gigGrow.component(.year, from: $0.start)
        })).sorted()
    }

    /// Six labels stay legible at phone width. If the driver has a longer
    /// history, the first point carries every earlier year and the remaining
    /// five retain their individual shape.
    private var allTimeYearGroups: [(label: String, years: Set<Int>)] {
        let years = yearsWithEarnings
        guard years.count > 6 else {
            return years.map {
                (String($0), Set([$0]))
            }
        }

        let recent = Array(years.suffix(5))
        let earlier = Set(years.dropLast(5))
        let earlierLabel = "≤" + String(earlier.max() ?? years[0])
        return [(earlierLabel, earlier)] + recent.map {
            (String($0), Set([$0]))
        }
    }

    private var dashboardWindow: Range<Date> {
        scope.window(
            recordDates: allShifts.map(\.start),
            now: anchor
        )
    }

    private var historyShifts: [Shift] {
        allShifts.filter { dashboardWindow.contains($0.start) }
    }

    private var historyDays: [DashboardHistoryDay] {
        let grouped = Dictionary(grouping: historyShifts) {
            Calendar.gigGrow.startOfDay(for: $0.start)
        }
        return grouped.keys.sorted(by: >).map {
            DashboardHistoryDay(date: $0, items: grouped[$0] ?? [])
        }
    }

    // MARK: Tax / maintenance

    private var setAsideTiles: some View {
        TilePair {
            StatTile(
                eyebrow: "Taxes to save",
                value: Money.whole(snapshot.taxesToSave),
                footnote: "\(Int(snapshot.taxRate))% set aside",
                footnoteColor: GG.Palette.violet300.opacity(0.85),
                fill: GG.Surface.glassBright
            )
        } right: {
            StatTile(
                eyebrow: "Maintenance",
                value: Money.whole(snapshot.maintenanceThisWeek),
                footnote: "Fund \(Money.whole(snapshot.maintenanceFund))",
                footnoteColor: GG.Palette.blue300.opacity(0.85),
                fill: GG.Surface.glassBright
            )
        }
    }

    // MARK: Earnings by app

    private var earningsByApp: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Earnings by app")
                        .ggText(GG.Typo.cardTitle, tracking: GG.Typo.cardTitleTracking)
                    Spacer()
                    // Not "connected" — nothing is connected to anything.
                    // These are apps the driver logged by hand.
                    Text("\(snapshot.platforms.count) \(scope.activityLabel)")
                        .ggText(GG.Typo.captionMuted, color: Color.white.opacity(0.40))
                }

                ForEach(snapshot.platforms) { platform in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(platform.name)
                                .ggText(GG.Typo.body, color: GG.Ink.body)
                            Spacer()
                            Text(Money.cents(snapshot.amount(for: platform)))
                                .ggText(.system(size: 14.5, weight: .semibold), tracking: -0.15)
                        }
                        ProgressBar(
                            progress: snapshot.normalisedShare(for: platform),
                            height: 6,
                            fill: platform.barGradient
                        )
                    }
                }
            }
        }
    }

    // MARK: Rates

    private var rateTiles: some View {
        TilePair {
            StatTile(eyebrow: "Per hour", value: snapshot.perHourLabel)
        } right: {
            StatTile(
                eyebrow: "Per mile",
                value: snapshot.perMileLabel,
                footnote: snapshot.mileage == 0 ? "Add miles to a shift" : nil,
                footnoteColor: GG.Ink.muted
            )
        }
    }

    // MARK: Hours & mileage

    private var hoursCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Online hours")
                        unitValue(Hours.clock(snapshot.onlineHours), unit: "")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Eyebrow(text: "Mileage")
                        unitValue(Num.grouped(snapshot.mileage), unit: " mi")
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    // The active/idle bar was here. It's gone with the field
                    // that fed it: nobody can report their own waiting time
                    // accurately, so the split was a guess drawn as a
                    // measurement.
                    // Was "Active 4h 22m · Idle 0m". No gig app publishes the
                    // split — Uber gives online time and nothing else — so idle
                    // was zero on every imported shift and the pair read as a
                    // measurement rather than as an empty field. Online time is
                    // the right denominator anyway: waiting for a ping is part
                    // of the job, and dividing by "booked" hours only would
                    // flatter the rate.
                    Text("Time online, waiting included")
                        .ggText(.system(size: 12.5, weight: .regular), color: GG.Ink.muted)
                }
            }
        }
    }

    /// Big figure with a smaller, dimmer unit suffix.
    private func unitValue(_ value: String, unit: String) -> some View {
        (
            Text(value)
                .font(GG.Typo.metricLarge)
                .foregroundColor(.white)
            + Text(unit)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Color.white.opacity(0.45))
        )
        .tracking(GG.Typo.metricLargeTracking)
    }

    // MARK: Trends

    private var trendTiles: some View {
        TilePair {
            StatTile(
                eyebrow: "Weekly trend",
                value: snapshot.weeklyChange,
                valueFont: GG.Typo.headline,
                valueTracking: GG.Typo.headlineTracking,
                valueColor: GG.Palette.mint
            ) {
                Sparkline(points: snapshot.series.daily
                            .chartPoints(box: ChartData.sparklineBox),
                          color: GG.Palette.mint.opacity(0.8))
                    .padding(.top, 8)
            }
        } right: {
            StatTile(
                eyebrow: "Monthly trend",
                value: snapshot.monthlyChange,
                valueFont: GG.Typo.headline,
                valueTracking: GG.Typo.headlineTracking,
                valueColor: GG.Palette.blue300
            ) {
                Sparkline(points: snapshot.series.monthly
                            .chartPoints(box: ChartData.sparklineBox),
                          color: GG.Palette.blue300.opacity(0.8))
                    .padding(.top, 8)
            }
        }
    }
}

private struct DashboardHistoryDay: Identifiable {
    let date: Date
    let items: [Shift]

    var id: Date { date }
    var gross: Double { items.reduce(0) { $0 + $1.gross } }
    var hours: Double { items.reduce(0) { $0 + $1.hours } }
    var miles: Double { items.reduce(0) { $0 + $1.miles } }
    var tips: Double {
        items.flatMap(\.earningItems).reduce(0) { $0 + $1.tips }
    }
    var promotions: Double {
        items.flatMap(\.earningItems).reduce(0) { $0 + $1.promotions }
    }
    var isEstimated: Bool {
        !items.isEmpty && items.allSatisfy {
            $0.note?.hasPrefix("From a weekly screenshot") == true
        }
    }
}

#Preview("Dashboard") {
    DashboardView(
        snapshot: .mock,
        scope: .constant(.week),
        anchor: .constant(.now)
    )
        .preferredColorScheme(.dark)
}

#Preview("Dashboard — empty") {
    DashboardView(
        snapshot: .empty,
        scope: .constant(.week),
        anchor: .constant(.now)
    )
        .preferredColorScheme(.dark)
}

private enum DashboardChartMode {
    case cumulative
    case period

    mutating func toggle() {
        self = self == .cumulative ? .period : .cumulative
    }

    func title(for scope: DashboardScope) -> String {
        switch self {
        case .cumulative:
            return "RUNNING TOTAL"
        case .period:
            switch scope {
            case .week: return "EARNINGS BY DAY"
            case .year: return "EARNINGS BY MONTH"
            case .allTime: return "EARNINGS BY YEAR"
            }
        }
    }

    func accessibilityLabel(for scope: DashboardScope) -> String {
        switch self {
        case .cumulative:
            return "Running earnings total chart"
        case .period:
            switch scope {
            case .week: return "Daily earnings bar chart"
            case .year: return "Monthly earnings bar chart"
            case .allTime: return "Yearly earnings bar chart"
            }
        }
    }
}
