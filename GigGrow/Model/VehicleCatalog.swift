//
//  VehicleCatalog.swift
//  GigGrow
//
//  An offline catalog for the vehicle picker. The editor should be useful in
//  a parking garage or during onboarding without waiting on a network API.
//  "Other" remains available because no bundled catalog can stay exhaustive.
//

import Foundation

struct VehicleMakeOption: Identifiable, Hashable {
    let name: String
    let models: [String]

    var id: String { name }
}

enum VehicleCatalog {
    static let other = "Other"

    static let makes: [VehicleMakeOption] = [
        .init(name: "Acura", models: ["ILX", "Integra", "MDX", "RDX", "TLX"]),
        .init(name: "Audi", models: ["A3", "A4", "A5", "A6", "Q3", "Q4 e-tron", "Q5", "Q7", "Q8 e-tron", "e-tron GT"]),
        .init(name: "BMW", models: ["2 Series", "3 Series", "4 Series", "5 Series", "X1", "X2", "X3", "X5", "i4", "i5", "iX"]),
        .init(name: "Buick", models: ["Enclave", "Encore", "Encore GX", "Envision", "Envista", "LaCrosse"]),
        .init(name: "Cadillac", models: ["CT4", "CT5", "Escalade", "LYRIQ", "OPTiq", "XT4", "XT5", "XT6"]),
        .init(name: "Chevrolet", models: ["Blazer", "Blazer EV", "Bolt EUV", "Bolt EV", "Equinox", "Equinox EV", "Impala", "Malibu", "Silverado", "Spark", "Suburban", "Tahoe", "Trailblazer", "Trax", "Volt"]),
        .init(name: "Chrysler", models: ["200", "300", "Pacifica", "Pacifica Hybrid", "Voyager"]),
        .init(name: "Dodge", models: ["Charger", "Dart", "Durango", "Grand Caravan", "Hornet", "Journey"]),
        .init(name: "Fiat", models: ["500", "500e", "500L", "500X"]),
        .init(name: "Ford", models: ["Bronco", "Bronco Sport", "Edge", "Escape", "Expedition", "Explorer", "F-150", "F-150 Lightning", "Fiesta", "Focus", "Fusion", "Maverick", "Mustang Mach-E", "Ranger", "Transit"]),
        .init(name: "Genesis", models: ["G70", "G80", "G90", "GV60", "GV70", "GV80"]),
        .init(name: "GMC", models: ["Acadia", "Canyon", "Hummer EV", "Sierra", "Terrain", "Yukon"]),
        .init(name: "Honda", models: ["Accord", "Civic", "Clarity", "CR-V", "CR-V Hybrid", "Fit", "HR-V", "Insight", "Odyssey", "Passport", "Pilot", "Prologue", "Ridgeline"]),
        .init(name: "Hyundai", models: ["Accent", "Elantra", "Elantra Hybrid", "Ioniq", "IONIQ 5", "IONIQ 6", "Kona", "Kona Electric", "Palisade", "Santa Fe", "Sonata", "Sonata Hybrid", "Tucson", "Venue"]),
        .init(name: "Infiniti", models: ["Q50", "Q60", "QX30", "QX50", "QX55", "QX60", "QX80"]),
        .init(name: "Jaguar", models: ["E-PACE", "F-PACE", "I-PACE", "XE", "XF"]),
        .init(name: "Jeep", models: ["Cherokee", "Compass", "Gladiator", "Grand Cherokee", "Grand Cherokee 4xe", "Renegade", "Wagoneer", "Wrangler", "Wrangler 4xe"]),
        .init(name: "Kia", models: ["Carnival", "EV6", "EV9", "Forte", "K5", "Niro", "Niro EV", "Optima", "Rio", "Seltos", "Sorento", "Soul", "Sportage", "Stinger", "Telluride"]),
        .init(name: "Land Rover", models: ["Defender", "Discovery", "Discovery Sport", "Range Rover", "Range Rover Evoque", "Range Rover Sport", "Range Rover Velar"]),
        .init(name: "Lexus", models: ["ES", "GX", "IS", "LS", "LX", "NX", "RC", "RX", "RZ", "UX"]),
        .init(name: "Lincoln", models: ["Aviator", "Continental", "Corsair", "MKC", "MKZ", "Nautilus", "Navigator"]),
        .init(name: "Lucid", models: ["Air", "Gravity"]),
        .init(name: "Mazda", models: ["CX-3", "CX-30", "CX-5", "CX-50", "CX-9", "CX-90", "Mazda3", "Mazda6", "MX-30"]),
        .init(name: "Mercedes-Benz", models: ["A-Class", "C-Class", "CLA", "E-Class", "EQA", "EQB", "EQE", "EQS", "GLA", "GLB", "GLC", "GLE", "GLS"]),
        .init(name: "MINI", models: ["Clubman", "Cooper", "Cooper Electric", "Countryman"]),
        .init(name: "Mitsubishi", models: ["Eclipse Cross", "Mirage", "Outlander", "Outlander PHEV", "RVR"]),
        .init(name: "Nissan", models: ["Altima", "Ariya", "Armada", "Frontier", "Kicks", "Leaf", "Maxima", "Murano", "Pathfinder", "Rogue", "Sentra", "Titan", "Versa"]),
        .init(name: "Polestar", models: ["Polestar 2", "Polestar 3", "Polestar 4"]),
        .init(name: "Porsche", models: ["Cayenne", "Macan", "Panamera", "Taycan"]),
        .init(name: "Ram", models: ["1500", "2500", "ProMaster", "ProMaster City"]),
        .init(name: "Rivian", models: ["R1S", "R1T"]),
        .init(name: "Scion", models: ["FR-S", "iA", "iM", "iQ", "tC", "xB", "xD"]),
        .init(name: "Subaru", models: ["Ascent", "Crosstrek", "Forester", "Impreza", "Legacy", "Outback", "Solterra", "WRX"]),
        .init(name: "Tesla", models: ["Model 3", "Model S", "Model X", "Model Y", "Cybertruck"]),
        .init(name: "Toyota", models: ["4Runner", "Avalon", "bZ4X", "Camry", "Camry Hybrid", "Corolla", "Corolla Cross", "C-HR", "Grand Highlander", "Highlander", "Land Cruiser", "Mirai", "Prius", "Prius Prime", "RAV4", "RAV4 Hybrid", "RAV4 Prime", "Sequoia", "Sienna", "Tacoma", "Tundra", "Venza"]),
        .init(name: "Volkswagen", models: ["Arteon", "Atlas", "Atlas Cross Sport", "Golf", "ID.4", "ID. Buzz", "Jetta", "Passat", "Taos", "Tiguan"]),
        .init(name: "Volvo", models: ["C40 Recharge", "EX30", "EX40", "EX90", "S60", "S90", "V60", "XC40", "XC60", "XC90"])
    ]

    static var makeNames: [String] { makes.map(\.name) }

    static func models(for make: String) -> [String] {
        option(for: make)?.models ?? []
    }

    static func canonicalMake(matching value: String) -> String? {
        option(for: value)?.name
    }

    static func canonicalModel(matching value: String, for make: String) -> String? {
        let normalized = value.normalizedVehicleName
        return models(for: make).first {
            $0.normalizedVehicleName == normalized
        }
    }

    private static func option(for make: String) -> VehicleMakeOption? {
        let normalized = make.normalizedVehicleName
        return makes.first { $0.name.normalizedVehicleName == normalized }
    }
}

private extension String {
    var normalizedVehicleName: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "en_US"))
    }
}
