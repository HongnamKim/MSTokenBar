import Foundation

/// Gunpla sprites ship inside the app bundle (`Resources/Gunpla/Sprites`); they never touch the network.
enum BundledSprites {
    /// Per-grade art, then the body-type art, then the grey silhouette. A name only counts when the
    /// file exists in the bundle, so missing art degrades to the silhouette instead of failing.
    static func resourceName(speciesID: Int, catalog: MachineCatalog = .shared,
                             bundle: Bundle = GunplaResources.bundle) -> String? {
        guard let decoded = GunplaID.decode(speciesID) else { return nil }
        let sprites = catalog.machine(id: decoded.machineID)?.sprites
        let bodyKey = decoded.grade.bodyType == .sd ? "sdBody" : "realBody"
        for key in [decoded.grade.rawValue, bodyKey] {
            if let name = sprites?[key], url(name, "gif", bundle) != nil { return name }
        }
        return decoded.grade.bodyType == .sd ? "silhouette-sd" : "silhouette-real"
    }

    static func gifData(speciesID: Int, catalog: MachineCatalog = .shared,
                        bundle: Bundle = GunplaResources.bundle) -> Data? {
        guard let name = resourceName(speciesID: speciesID, catalog: catalog, bundle: bundle),
              let url = url(name, "gif", bundle) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func boxPNG(bundle: Bundle = GunplaResources.bundle) -> Data? {
        url("box", "png", bundle).flatMap { try? Data(contentsOf: $0) }
    }

    private static func url(_ name: String, _ ext: String, _ bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "Gunpla/Sprites")
    }
}
