import Foundation

/// Paint tool set — permanent purchases that raise the variant (shiny) odds one step each.
enum ToolSet {
    /// Variant roll denominator per owned tool count: base 1/32, then 1/26 → 1/21 → 1/16 → 1/12.
    static let denominators: [UInt64] = [32, 26, 21, 16, 12]

    static func shinyDenominator(toolLevel: Int) -> UInt64 {
        denominators[min(max(toolLevel, 0), denominators.count - 1)]
    }
}
