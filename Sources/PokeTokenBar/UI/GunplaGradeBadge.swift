import SwiftUI

/// Shared package-style marks. One static image serves every machine of the same grade.
@MainActor
struct GunplaGradeBadge: View {
    let grade: GunplaGrade
    let spriteSize: CGFloat

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

    private static func pixelScale(for size: CGFloat) -> CGFloat {
        min(3, max(1.5, (size / 48).rounded(.down)))
    }

    /// Keep the badge below the floating pet, with a two-point gap even in the smallest window.
    static func footerHeight(for size: CGFloat, grade: GunplaGrade?) -> CGFloat {
        guard let grade else { return 0 }
        let nativeHeight = images[grade]?.size.height ?? 13
        return ceil(nativeHeight * pixelScale(for: size)) + 2
    }

    var body: some View {
        Group {
            if spriteSize >= 48, let image = Self.images[grade] {
                let scale = Self.pixelScale(for: spriteSize)
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: image.size.width * scale, height: image.size.height * scale)
            } else {
                Text(verbatim: grade.label)
                    .font(.system(size: min(18, max(7, spriteSize * 0.14)), weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: grade.label))
        .allowsHitTesting(false)
    }
}
