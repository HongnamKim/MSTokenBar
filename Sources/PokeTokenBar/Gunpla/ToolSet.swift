import Foundation

/// Paint tool set — permanent purchases that raise the variant (shiny) odds one step each.
enum ToolSet {
    /// Variant roll denominator per owned tool count: base 1/32, then 1/26 → 1/21 → 1/16 → 1/12.
    static let denominators: [UInt64] = [32, 26, 21, 16, 12]

    static func shinyDenominator(toolLevel: Int) -> UInt64 {
        denominators[min(max(toolLevel, 0), denominators.count - 1)]
    }

    /// Tools are bought strictly in this order.
    static let order: [ItemKind] = [.maskingTape, .panelLinePen, .paintSet, .airbrush]

    static let prices: [ItemKind: Int] = [
        .maskingTape: 1_000_000_000,
        .panelLinePen: 1_500_000_000,
        .paintSet: 2_000_000_000,
        .airbrush: 3_000_000_000,
    ]

    /// Count of tools owned contiguously from the start of `order` (a tool owned past a gap does not count).
    static func level(inventory: [String: Int]) -> Int {
        order.prefix { (inventory[$0.rawValue] ?? 0) > 0 }.count
    }

    /// The one tool that can be bought now, or nil when all are owned.
    static func nextPurchasable(inventory: [String: Int]) -> ItemKind? {
        let owned = level(inventory: inventory)
        return owned < order.count ? order[owned] : nil
    }
}
