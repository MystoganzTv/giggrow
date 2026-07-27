//
//  Subscription.swift
//  GigGrow
//
//  Plans and entitlements.
//
//  Pricing was set against the market rather than picked: Gridwise Plus is
//  $14.99/mo or $107.99/yr, Solo runs $8–$15/mo billed annually, Stride is
//  free. The design's original $20/mo sat above every competitor for a
//  smaller product, so Pro undercuts the field instead.
//
//  Note what is *not* gated: manual entry, the dashboard, the analytics and
//  the tax set-aside all stay free. Automatic sync is a commodity — Gridwise
//  and Solo both buy it from the same aggregator — so it can't carry a
//  subscription on its own. The maintenance reserve can, because neither
//  competitor treats the car as an asset that needs one.
//

import Foundation

// MARK: - Tier

enum PlanTier: String, Codable, CaseIterable {
    case free
    case pro

    var title: String {
        switch self {
        case .free: return "GigGrow"
        case .pro:  return "GigGrow Pro"
        }
    }
}

// MARK: - Price

struct PlanPrice: Hashable {
    let amount: Decimal
    let period: Period

    enum Period: Hashable {
        case month
        case year
    }

    var formatted: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        let value = f.string(from: amount as NSDecimalNumber) ?? "$0"
        return value
    }

    var perPeriodLabel: String {
        switch period {
        case .month: return "\(formatted) / month"
        case .year:  return "\(formatted) / year"
        }
    }

    /// Annual plans quoted as a monthly figure, for the "works out to" line.
    var monthlyEquivalent: String {
        guard period == .year else { return formatted }
        let monthly = amount / 12
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.roundingMode = .down
        return f.string(from: monthly as NSDecimalNumber) ?? formatted
    }
}

// MARK: - Plan

enum Plan {
    /// $9.99/mo — under Gridwise Plus ($14.99) and Solo Pro Plus ($15).
    static let proMonthly = PlanPrice(amount: 9.99, period: .month)

    /// $79.99/yr — works out to $6.66/mo, and 26% under Gridwise's $107.99.
    static let proAnnual = PlanPrice(amount: 79.99, period: .year)

    /// Saving when paying yearly, as a whole percentage.
    static var annualSavingPercent: Int {
        let monthlyTotal = proMonthly.amount * 12
        guard monthlyTotal > 0 else { return 0 }
        let saving = (monthlyTotal - proAnnual.amount) / monthlyTotal * 100
        return Int(truncating: NSDecimalNumber(decimal: saving))
    }
}

// MARK: - Features

/// Everything that can be gated. Adding a case forces every switch that
/// decides access to account for it.
enum ProFeature: String, CaseIterable, Identifiable {
    case automaticSync
    case maintenanceReserve
    case costPerMile
    case serviceSchedule
    case dataExport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automaticSync:      return "Automatic earnings sync"
        case .maintenanceReserve: return "Maintenance reserve"
        case .costPerMile:        return "True cost per mile"
        case .serviceSchedule:    return "Service schedule"
        case .dataExport:         return "Export for your accountant"
        }
    }

    var detail: String {
        switch self {
        case .automaticSync:
            return "Link your platforms and stop typing shifts in by hand."
        case .maintenanceReserve:
            return "Set aside a slice of every payout so the next repair is already paid for."
        case .costPerMile:
            return "Fuel, maintenance and depreciation per mile — what the car actually costs you."
        case .serviceSchedule:
            return "Track what's due by mileage, not by memory."
        case .dataExport:
            return "Mileage, earnings and expenses as CSV or PDF."
        }
    }

    /// The reserve leads the paywall. Sync is table stakes — both competitors
    /// buy it from the same aggregator — so it can't be the reason to pay.
    static var orderedForPaywall: [ProFeature] {
        [.maintenanceReserve, .costPerMile, .automaticSync, .serviceSchedule, .dataExport]
    }
}

// MARK: - Entitlement

/// What the current user may do. Built from the stored tier today; when
/// StoreKit lands, this is the only type that needs to change.
struct Entitlement: Equatable {
    let tier: PlanTier

    static let free = Entitlement(tier: .free)
    static let pro = Entitlement(tier: .pro)

    var isPro: Bool { tier == .pro }

    func allows(_ feature: ProFeature) -> Bool {
        switch tier {
        case .pro:  return true
        case .free: return false
        }
    }

    /// Free users still see what the reserve *would* hold. A wedge nobody can
    /// see isn't a wedge — hiding the number entirely would remove the only
    /// reason to upgrade.
    func showsPreview(of feature: ProFeature) -> Bool {
        !allows(feature) && feature == .maintenanceReserve
    }
}
