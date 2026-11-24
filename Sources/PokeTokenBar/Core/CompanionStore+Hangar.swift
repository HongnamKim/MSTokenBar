import Foundation

/// 격납고 — one cell per owned machine, built from the dex's synthetic (machine × grade) species.
extension CompanionStore {
    /// Owned machines, sorted by series order and then machine id. Species that are not catalog
    /// machines (Pokémon left in an old save) have no cell.
    var hangarCells: [HangarCell] {
        var owned: [Int: Set<GunplaGrade>] = [:]
        var raising: Set<Int> = []
        for species in dexSpecies {
            guard let decoded = GunplaID.decode(species.id), catalog.machine(id: decoded.machineID) != nil else { continue }
            owned[decoded.machineID, default: []].insert(decoded.grade)
            if species.isRaising { raising.insert(decoded.machineID) }
        }
        let order = hangarOrder
        return owned.compactMap { machineID, grades -> HangarCell? in
            guard let machine = catalog.machine(id: machineID) else { return nil }
            return HangarCell(machineID: machineID, ownedGrades: grades, releasedGrades: machine.grades,
                              isVariant: machine.isVariant, isRaising: raising.contains(machineID))
        }
        .sorted { order($0) < order($1) }
    }

    /// Base machines not built in any grade yet, in hangar order — the grid's silhouettes. Custom units
    /// (전용기) stay hidden until built, like the series chips that count base machines only.
    var unbuiltHangarCells: [HangarCell] {
        let built = Set(hangarCells.map(\.machineID))
        let order = hangarOrder
        return catalog.machines
            .filter { !$0.isVariant && !built.contains($0.id) }
            .map { HangarCell(machineID: $0.id, ownedGrades: [], releasedGrades: $0.grades,
                              isVariant: false, isRaising: false) }
            .sorted { order($0) < order($1) }
    }

    /// Hangar order key: series order, then machine id.
    private var hangarOrder: (HangarCell) -> (Int, Int) {
        let seriesOrder = Dictionary(catalog.series.map { ($0.id, $0.order) }, uniquingKeysWith: { first, _ in first })
        let catalog = catalog
        return { cell in
            (catalog.machine(id: cell.machineID).flatMap { seriesOrder[$0.series] } ?? .max, cell.machineID)
        }
    }

    /// The name a cell shows: the machine's name once built, "???" on a silhouette.
    func hangarCellName(_ cell: HangarCell) -> String {
        cell.isBuilt ? machineName(cell.machineID) : "???"
    }

    func hangarCell(machineID: Int) -> HangarCell? {
        hangarCells.first { $0.machineID == machineID }
    }

    /// Per-series progress in catalog order. Drives the hangar's series chips and the completion badges.
    var dexCompletions: [SeriesCompletion] {
        HangarProgress.completions(owned: hangarCells, catalog: catalog)
    }

    /// Every completion badge currently earned — derived, never persisted (ownership only grows).
    var earnedDexBadges: [DexBadge] {
        HangarProgress.earnedBadges(dexCompletions)
    }

    /// The detail page a cell opens: its highest owned grade (`DexSpecies.collectionID`).
    func hangarDetailCollectionID(_ cell: HangarCell) -> String {
        String(hangarRepresentativeSpeciesID(cell))
    }

    /// The species a cell stands for — its highest owned grade. Also what "set as representative" picks.
    func hangarRepresentativeSpeciesID(_ cell: HangarCell) -> Int {
        GunplaID.encode(machineID: cell.machineID, grade: cell.ownedGrades.max() ?? cell.releasedGrades[0])
    }

    /// The representative species is one of this machine's grades.
    func isRepresentative(_ cell: HangarCell) -> Bool {
        state.representativeSpeciesID.flatMap(GunplaID.decode)?.machineID == cell.machineID
    }

    /// Hover line for a floating pet: "MS-09 · HG Dom" in the current language, or the box name.
    func hoverTitle(speciesID: Int?) -> String {
        guard let speciesID, let decoded = GunplaID.decode(speciesID) else { return l.eggName(state.eggTier) }
        let name = "\(decoded.grade.label) \(machineName(decoded.machineID))"
        guard let model = catalog.machine(id: decoded.machineID)?.modelNumber else { return name }
        return "\(model) · \(name)"
    }

    /// Machine name in the current language, or "#id" when the catalog does not know it.
    func machineName(_ machineID: Int) -> String {
        catalog.machine(id: machineID).flatMap { state.language.resolveName($0.names) } ?? "#\(machineID)"
    }

    /// Series title in the current language, or its id when unknown.
    func seriesName(_ seriesID: String) -> String {
        catalog.series.first { $0.id == seriesID }.flatMap { state.language.resolveName($0.names) } ?? seriesID
    }

    /// Tooltip / notification label for a badge, with its series name resolved.
    func dexBadgeLabel(_ badge: DexBadge) -> String {
        l.dexBadgeLabel(badge, seriesName: badge.seriesID.map(seriesName) ?? "")
    }

    /// Filters and sorts hangar cells. The query matches the machine name in the current language or
    /// its model number; `variantOnly` keeps 전용기; `series` keeps one series.
    ///
    /// `includeUnbuilt` adds the silhouettes. They take part only in filters that do not reveal them:
    /// series, and the query by model number (the name stays hidden). A rarity or 전용기 filter shows
    /// built machines only. Number order interleaves them so the gaps show; name and rarity orders put
    /// them after the built machines, since both are unknown until built.
    func filteredHangarCells(
        query: String = "",
        rarity: Rarity? = nil,
        variantOnly: Bool = false,
        series: String? = nil,
        sort: DexSortOption = .numberAsc,
        includeUnbuilt: Bool = false
    ) -> [HangarCell] {
        let built = filteredBuiltHangarCells(query: query, rarity: rarity, variantOnly: variantOnly,
                                             series: series, sort: sort)
        guard includeUnbuilt, rarity == nil, !variantOnly else { return built }
        let matcher = DexSearchMatcher(query)
        let unbuilt = unbuiltHangarCells.filter { cell in
            guard let machine = catalog.machine(id: cell.machineID) else { return false }
            if let series, machine.series != series { return false }
            if let matcher, !matcher.matches(name: "", modelNumber: machine.modelNumber) { return false }
            return true
        }
        let order = hangarOrder
        switch sort {
        case .numberAsc: return (built + unbuilt).sorted { order($0) < order($1) }
        case .numberDesc: return (built + unbuilt).sorted { order($0) > order($1) }
        case .nameAsc, .nameDesc, .rarityDesc: return built + unbuilt
        }
    }

    private func filteredBuiltHangarCells(
        query: String, rarity: Rarity?, variantOnly: Bool, series: String?, sort: DexSortOption
    ) -> [HangarCell] {
        let matcher = DexSearchMatcher(query)
        let cells = hangarCells.filter { cell in
            guard let machine = catalog.machine(id: cell.machineID) else { return false }
            if let rarity, machine.rarity != rarity { return false }
            if variantOnly, !cell.isVariant { return false }
            if let series, machine.series != series { return false }
            if let matcher, !matcher.matches(name: machineName(cell.machineID), modelNumber: machine.modelNumber) {
                return false
            }
            return true
        }
        return sortHangarCells(cells, by: sort)
    }

    /// `cells` must be in hangar order (series, id); that order is the "number" order and the tie-break.
    private func sortHangarCells(_ cells: [HangarCell], by sort: DexSortOption) -> [HangarCell] {
        let rank = Dictionary(uniqueKeysWithValues: cells.enumerated().map { ($1.machineID, $0) })
        func hangarOrder(_ a: HangarCell, _ b: HangarCell) -> Bool { rank[a.machineID]! < rank[b.machineID]! }
        switch sort {
        case .numberAsc:
            return cells
        case .numberDesc:
            return cells.reversed()
        case .nameAsc, .nameDesc:
            let names = Dictionary(uniqueKeysWithValues: cells.map { ($0.machineID, machineName($0.machineID)) })
            let wanted: ComparisonResult = sort == .nameAsc ? .orderedAscending : .orderedDescending
            return cells.sorted {
                let cmp = names[$0.machineID]!.localizedCompare(names[$1.machineID]!)
                return cmp == .orderedSame ? hangarOrder($0, $1) : cmp == wanted
            }
        case .rarityDesc:
            func rarityRank(_ cell: HangarCell) -> Int { catalog.machine(id: cell.machineID)?.rarity.sortRank ?? 0 }
            return cells.sorted {
                rarityRank($0) != rarityRank($1) ? rarityRank($0) > rarityRank($1) : hangarOrder($0, $1)
            }
        }
    }
}
