//
//  FuelType.swift
//  GigGrow
//
//  What the car runs on, and what that changes.
//
//  This isn't cosmetic. An EV has no mpg — measuring it in miles per gallon
//  divides by a quantity that doesn't exist. Its efficiency is miles/kWh and its
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
    var efficiencyUnit: String { burnsFuel ? "mpg" : "miles/kWh" }

    /// Label above the efficiency tile.
    var efficiencyTitle: String { burnsFuel ? "Fuel efficiency" : "Energy efficiency" }

    /// Label above the per-mile running cost.
    var costPerMileTitle: String { burnsFuel ? "Fuel cost" : "Electricity cost" }

    /// Plain-language explanation shown under the cost rather than hiding
    /// the denominator in an abbreviation such as "Charging / mi".
    var costPerMileFootnote: String { "to drive 1 mile" }

    /// What the efficiency number means in terms of actual driving.
    var efficiencyFootnote: String {
        burnsFuel ? "miles from 1 gallon" : "miles from 1 kWh"
    }

    /// Placeholder shown in the editor, so the expected magnitude is obvious.
    var efficiencyPlaceholder: String { burnsFuel ? "39" : "3.5" }

    /// Whether a plausible efficiency value has been entered. An EV reading
    /// 39 miles/kWh is a mistyped mpg, and a car reading 3.5 mpg is the reverse.
    func isPlausibleEfficiency(_ value: Double) -> Bool {
        guard value > 0 else { return false }
        return burnsFuel ? (5...150).contains(value) : (0.5...10).contains(value)
    }

    /// Returns a type only when the make itself is unambiguous. This is used
    /// to repair old onboarding records that defaulted every vehicle to
    /// gasoline. It deliberately does not guess for mixed manufacturers.
    static func unambiguousType(make: String, model: String = "") -> FuelType? {
        let normalizedMake = make
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let normalizedModel = model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let electricOnlyMakes: Set<String> = [
            "tesla", "rivian", "lucid", "polestar"
        ]
        if electricOnlyMakes.contains(normalizedMake) { return .electric }
        if normalizedMake.isEmpty,
           electricOnlyMakes.contains(where: { normalizedModel.hasPrefix($0 + " ") }) {
            return .electric
        }
        return nil
    }
}
