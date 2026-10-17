import Foundation

enum ImpactFormat {
    static func mass(_ kg: Double) -> String {
        kg < 10 ? String(format: "%.1f kg", kg) : "\(Int(kg.rounded())) kg"
    }

    static func water(_ liters: Double) -> String {
        liters >= 10_000
            ? String(format: "%.0fk L", liters / 1000)
            : "\(Int(liters.rounded()).formatted()) L"
    }

    static func number(_ value: Double) -> String {
        value < 10 && value != value.rounded() ? String(format: "%.1f", value) : Int(value.rounded()).formatted()
    }
}

/// Relatable comparisons under each impact number (spec §10.3).
/// Each factor cites its source so the team can answer a judge who asks.
enum ImpactComparison {
    // US EPA WaterSense, "Showerheads": the average shower uses 2.1 gal/min and lasts about 8 minutes,
    // so 17.2 gal ≈ 65 L. https://www.epa.gov/watersense/showerheads
    static let litersPerShower = 65.0

    // US EPA, "Greenhouse Gas Emissions from a Typical Passenger Vehicle": about 400 g CO₂ per mile.
    // https://www.epa.gov/greenvehicles/greenhouse-gas-emissions-typical-passenger-vehicle
    static let co2KgPerMile = 0.4

    // A typical cotton T-shirt weighs about 0.2 kg. Approximate and not yet cited:
    // TODO(I-26): find a published source for this figure before the demo, or drop the comparison.
    static let kgPerTShirt = 0.2

    static func showers(_ liters: Double) -> String? { phrase(liters / litersPerShower, "shower", "showers") }
    static func miles(_ co2Kg: Double) -> String? { phrase(co2Kg / co2KgPerMile, "mile not driven", "miles not driven") }
    static func tshirts(_ kg: Double) -> String? { phrase(kg / kgPerTShirt, "T-shirt", "T-shirts") }

    /// "≈ 31 showers", or nil when it rounds to 0.
    private static func phrase(_ value: Double, _ one: String, _ many: String) -> String? {
        let count = Int(value.rounded())
        guard count > 0 else { return nil }
        return "≈ \(count.formatted()) \(count == 1 ? one : many)"
    }
}
