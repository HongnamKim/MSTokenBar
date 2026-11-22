import SwiftUI

/// What a `Badge` is colored by.
enum BadgeTint {
    case rarity(Rarity?)
    case accent, orange, secondary

    var color: Color {
        switch self {
        case .rarity(let rarity): rarityColor(rarity)
        case .accent: .accentColor
        case .orange: .orange
        case .secondary: .secondary
        }
    }
}

/// Small capsule label shared by rarity and status pills.
/// `.solid` = white text on the tint (rarity); `.tinted` = tint text on a faint tint (RAISING, boosts).
@MainActor
struct Badge<Label: View>: View {
    enum Style { case solid, tinted }

    let tint: BadgeTint
    var style: Style = .solid
    var size: CGFloat = 8
    var horizontalPadding: CGFloat = 5
    var verticalPadding: CGFloat = 1
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(style == .solid ? Color.white : tint.color)
            .padding(.horizontal, horizontalPadding).padding(.vertical, verticalPadding)
            .background(style == .solid ? tint.color : tint.color.opacity(0.14), in: Capsule())
    }
}

extension Badge where Label == Text {
    init(_ text: String, tint: BadgeTint, style: Style = .solid, size: CGFloat = 8) {
        self.init(tint: tint, style: style, size: size) { Text(text) }
    }
}
