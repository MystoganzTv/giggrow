//
//  FuelType.swift
//  GigGrow
//
//  What the car runs on, and what that changes.
//
//  This isn't cosmetic. An EV has no mpg — measuring it in miles per gallon
//  divides by a quantity that doesn't exist. Its efficiency is mi/kWh and its
//  per-mile running cost is electricity, which for a gig driver charging at
//  home is roughly a third of what fuel costs. Getting this wrong misstates
//  the single number the Vehicle screen exists to produce.
//

import Foundation

enum FuelType: String, Codable, CaseIterable, Identifiable {
    case gasoline
    case diesel
    case hybrid
    case pluginHybrid
    case electric

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gasoline:     return "Gasoline"
        case .diesel:       return "Diesel"
        case .hybrid:       return "Hybrid"
        case .pluginHybrid: return "Plug-in hybrid"
        case .electric:     return "Electric"
        }
    }

    /// Short form for the vehicle subtitle — "Electric · SVERIGE".
    var shortLabel: String {
        switch self {
        case .pluginHybrid: return "PHEV"
        default:            return label
        }
    }

    /// Burns fuel at all. A pure EV doesn't, so mpg is meaningless for it.
    var burnsFuel: Bool { self != .electric }

    /// What the efficiency figure is measured in.
    var efficiencyUnit: String { burnsFuel ? "mpg" : "mi/kWh" }

    /// Label above the efficiency tile.
    var efficiencyTitle: String { burnsFuel ? "Avg efficiency" : "Avg range" }

    /// Label above the per-mile running cost.
    var costPerMileTitle: String { burnsFuel ? "Fuel cost / mi" : "Charging / mi" }

    /// Placeholder shown in the editor, so the expected magnitude is obvious.
    var efficiencyPlaceholder: String { burnsFuel ? "39" : "3.5" }

    /// Whether a plausible efficiency value has been entered. An EV reading
    /// 39 mi/kWh is a mistyped mpg, and a car reading 3.5 mpg is the reverse.
    func isPlausibleEfficiency(_ value: Double) -> Bool {
        guard value > 0 else { return false }
        return burnsFuel ? (5...150).contains(value) : (0.5...10).contains(value)
    }
}
