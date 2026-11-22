import Foundation

enum GunplaResources {
    /// The packaged .app carries the SwiftPM resource bundle in Contents/Resources; `Bundle.module`
    /// (which falls back to the build machine's absolute path and can crash elsewhere) is only
    /// reached under `swift test` / `swift run`.
    static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "PokeTokenBar_PokeTokenBar", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}
