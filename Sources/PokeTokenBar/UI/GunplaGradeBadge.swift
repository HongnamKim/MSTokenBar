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

    private var markHeight: CGFloat { min(12, max(4, (spriteSize / 16).rounded())) }

    private func pixelScale(for image: NSImage) -> CGFloat {
        if isFloatingMark {
            // The four-letter MGSD mark also fits in the corner of a 48-point pet.
            return min(markHeight / image.size.height, (spriteSize / 6) / image.size.width)
        }
        return min(3, max(1.5, (spriteSize / 48).rounded(.down)))
    }

    var body: some View {
        Group {
            if spriteSize >= 48, let image = Self.images[grade] {
                let scale = pixelScale(for: image)
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
            } else {
                Text(verbatim: grade.label)
                    .font(.system(size: isFloatingMark ? markHeight * 0.65 : min(18, max(7, spriteSize * 0.14)),
                                  weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, isFloatingMark ? 1 : 3)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: grade.label))
        .allowsHitTesting(false)
    }
}
