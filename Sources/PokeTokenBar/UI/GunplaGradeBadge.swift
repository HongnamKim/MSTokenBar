import SwiftUI

/// Shared package-style marks. One static image serves every machine of the same grade.
@MainActor
struct GunplaGradeBadge: View {
    let grade: GunplaGrade
    let spriteSize: CGFloat
    var isFloatingMark = false

    static let images: [GunplaGrade: NSImage] = {
        var images: [GunplaGrade: NSImage] = [:]
        for grade in GunplaGrade.allCases {
            if let url = GunplaResources.bundle.url(forResource: grade.rawValue, withExtension: "png",
                                                    subdirectory: "Gunpla/GradeBadges") {
                images[grade] = NSImage(contentsOf: url)
            }
        }
        return images
    }()

    private var badgeScale: CGFloat { isFloatingMark ? 0.5 : 1 }

    /// Pixel scale steps every 48pt so the art stays crisp. In-app sprites cap at 3x; the floating
    /// pet can grow to 384pt, so its corner mark keeps growing with the pet instead of stopping at 144pt.
    nonisolated static func imageScale(spriteSize: CGFloat, isFloatingMark: Bool) -> CGFloat {
        let step = max(1.5, (spriteSize / 48).rounded(.down))
        return isFloatingMark ? step * 0.5 : min(3, step)
    }

    var body: some View {
        Group {
            if spriteSize >= 48, let image = Self.images[grade] {
                let scale = Self.imageScale(spriteSize: spriteSize, isFloatingMark: isFloatingMark)
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
            } else {
                Text(verbatim: grade.label)
                    .font(.system(size: min(18, max(7, spriteSize * 0.14)) * badgeScale,
                                  weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3 * badgeScale)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: grade.label))
        .allowsHitTesting(false)
    }
}
