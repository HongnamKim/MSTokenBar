import Foundation

/// What the build record card shows for one build. Pure: no store, clock or localization.
struct BuildRecordSummary: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case provider(id: String, name: String)   // name = display name, or the id when the tool is not registered
        case sandpaper
        case unattributed
    }
    struct Amount: Equatable, Sendable { let source: Source; let value: Int }
    struct Row: Equatable, Sendable {
        let speciesID: Int
        let reachedAt: Date?
        let isRecorded: Bool      // false = the build has no stage for this grade
        let tokens: Int           // all tools together
        let sandpaper: Int
        let unattributed: Int
        let amounts: [Amount]     // display order, values > 0 only; empty when not recorded
        var total: Int { tokens + sandpaper + unattributed }
    }
    enum End: Equatable, Sendable { case raising, completed(Date?), stopped(Date?) }
    enum Duration: Equatable, Sendable { case sameDay, days(Int), dayNumber(Int) }

    let openedAt: Date?
    let firstRecordedSpeciesID: Int   // the grade the header names when openedAt is nil
    let end: End
    let rows: [Row]                   // one per entry.chainOrder element, in that order
    let totals: [Amount]              // whole build, display order, values > 0 only

    var total: Int { rows.reduce(0) { $0 + $1.total } }
    var largestRowTotal: Int { rows.map(\.total).max() ?? 0 }

    /// nil = no card: the entry has no record, or none of its grades has a stage.
    init?(entry: DexEntry, isRaising: Bool, providerNames: [String: String]) {
        guard let log = entry.buildLog else { return nil }
        var tokenTotals: [String: Int] = [:]
        var sandpaperTotal = 0
        var unattributedTotal = 0
        var rows: [Row] = []
        for speciesID in entry.chainOrder {
            guard let stage = log.stages.first(where: { $0.speciesID == speciesID }) else {
                rows.append(Row(speciesID: speciesID, reachedAt: nil, isRecorded: false,
                                tokens: 0, sandpaper: 0, unattributed: 0, amounts: []))
                continue
            }
            for (key, value) in stage.tokensByProvider { tokenTotals[key, default: 0] += value }
            sandpaperTotal += stage.sandpaper
            unattributedTotal += stage.unattributed
            rows.append(Row(speciesID: speciesID, reachedAt: stage.reachedAt, isRecorded: true,
                            tokens: stage.tokensByProvider.values.reduce(0, +),
                            sandpaper: stage.sandpaper, unattributed: stage.unattributed,
                            amounts: Self.amounts(tokens: stage.tokensByProvider, sandpaper: stage.sandpaper,
                                                  unattributed: stage.unattributed, names: providerNames)))
        }
        guard let first = rows.first(where: \.isRecorded) else { return nil }
        self.openedAt = log.openedAt
        self.firstRecordedSpeciesID = first.speciesID
        self.end = isRaising ? .raising : entry.isReleased ? .stopped(entry.caughtAt) : .completed(entry.caughtAt)
        self.rows = rows
        self.totals = Self.amounts(tokens: tokenTotals, sandpaper: sandpaperTotal,
                                   unattributed: unattributedTotal, names: providerNames)
    }

    /// nil when the opening time is unknown, or the build ended at an unknown time.
    func duration(now: Date, calendar: Calendar) -> Duration? {
        guard let openedAt else { return nil }
        let endedAt: Date
        switch end {
        case .raising: endedAt = now
        case .completed(let date), .stopped(let date):
            guard let date else { return nil }
            endedAt = date
        }
        let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: openedAt),
                                                  to: calendar.startOfDay(for: endedAt)).day ?? 0)
        if case .raising = end { return .dayNumber(days + 1) }
        return days == 0 ? .sameDay : .days(days)
    }

    /// Tools by value descending, then name, then id; then sandpaper; then unattributed. Zero values are left out.
    private static func amounts(tokens: [String: Int], sandpaper: Int, unattributed: Int,
                                names: [String: String]) -> [Amount] {
        let tools = tokens.filter { $0.value > 0 }
            .map { (id: $0.key, name: names[$0.key] ?? $0.key, value: $0.value) }
            .sorted { l, r in
                if l.value != r.value { return l.value > r.value }
                if l.name != r.name { return l.name < r.name }
                return l.id < r.id
            }
            .map { Amount(source: .provider(id: $0.id, name: $0.name), value: $0.value) }
        var out = tools
        if sandpaper > 0 { out.append(Amount(source: .sandpaper, value: sandpaper)) }
        if unattributed > 0 { out.append(Amount(source: .unattributed, value: unattributed)) }
        return out
    }
}
