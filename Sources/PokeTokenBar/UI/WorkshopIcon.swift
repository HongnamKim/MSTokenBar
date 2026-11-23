import SwiftUI

/// Original pixel art shared by the companion, hangar, shop and menu bar.
enum WorkshopArt: String, CaseIterable {
    case box, airbrush, prayer, warning, hourglass, update
    case sandingSponge = "sanding-sponge"
    case maskingTape = "masking-tape"
    case panelLinePen = "panel-line-pen"
    case paintSet = "paint-set"
    case seriesMedal = "series-medal"
    case customMedal = "custom-medal"
    case hangarTrophy = "hangar-trophy"
    case customMark = "custom-mark"

    init(item: ItemKind) {
        switch item {
        case .rareCandy: self = .sandingSponge
        case .maskingTape: self = .maskingTape
        case .panelLinePen: self = .panelLinePen
        case .paintSet: self = .paintSet
        case .airbrush: self = .airbrush
        }
    }

    init(badge: DexBadge) {
        switch badge {
        case .series: self = .seriesMedal
        case .seriesVariant, .allVariant: self = .customMedal
        case .all: self = .hangarTrophy
        }
    }

    @MainActor private static let images: [Self: NSImage] = {
        var images: [Self: NSImage] = [:]
        for art in allCases {
            if art == .box {
                images[art] = BundledSprites.boxPNG().flatMap { NSImage(data: $0) }
            } else if let url = GunplaResources.bundle.url(forResource: art.rawValue, withExtension: "png",
                                                          subdirectory: "Gunpla/Workshop") {
                images[art] = NSImage(contentsOf: url)
            }
        }
        return images
    }()

    @MainActor var image: NSImage? { Self.images[self] }
}

@MainActor
struct WorkshopIcon: View {
    let art: WorkshopArt
    let size: CGFloat
    let label: String?

    init(_ art: WorkshopArt, size: CGFloat, label: String? = nil) {
        self.art = art
        self.size = size
        self.label = label
    }

    var body: some View {
        Group {
            if let image = art.image {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(verbatim: label ?? ""))
        .accessibilityHidden(label == nil)
    }
}
