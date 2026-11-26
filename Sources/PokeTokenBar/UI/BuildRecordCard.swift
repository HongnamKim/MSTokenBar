import SwiftUI

/// The build record of one build on the machine detail page: a header, one row per grade of the chain
/// with a bar split by source, and the whole build's amounts by source.
@MainActor
struct BuildRecordCard: View {
    let summary: BuildRecordSummary
    let l: L
    let locale: Locale
    var now: Date = Date()
    var calendar: Calendar = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(l.catchLogTitle).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                if isRaising { Badge(l.dexRaising.uppercased(), tint: .accent, style: .tinted, size: 10) }
            }
            Text(Self.headerText(summary, l: l, locale: locale, now: now, calendar: calendar))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                ForEach(Array(summary.rows.enumerated()), id: \.offset) { index, row in
                    gradeRow(row, isRaisingRow: isRaising && index == summary.rows.count - 1)
                }
            }
            .font(.caption.monospacedDigit())
            if !summary.totals.isEmpty { footer }
        }
        .detailCard()
    }

    private var isRaising: Bool { summary.end == .raising }

    @ViewBuilder
    private func gradeRow(_ row: BuildRecordSummary.Row, isRaisingRow: Bool) -> some View {
        if row.amounts.isEmpty {
            GridRow { cells(row, isRaisingRow: isRaisingRow) }
        } else {
            let breakdown = Self.breakdownText(row.amounts, openedAtKnown: summary.openedAt != nil, l: l)
            GridRow { cells(row, isRaisingRow: isRaisingRow) }
                .help(breakdown)
                .accessibilityValue(breakdown)
        }
    }

    @ViewBuilder
    private func cells(_ row: BuildRecordSummary.Row, isRaisingRow: Bool) -> some View {
        Text(Self.gradeLabel(row.speciesID))
            .fontWeight(.semibold)
            .foregroundStyle(isRaisingRow ? Color.accentColor : Color.primary)
        Text(row.reachedAt.map { Self.dateText($0, year: false, locale: locale, calendar: calendar) } ?? "—")
            .foregroundStyle(.secondary)
        bar(row)
        Text(row.isRecorded ? TokenFormatter.compact(row.total) : "—")
            .gridColumnAlignment(.trailing)
    }

    /// As wide as the row's share of the largest row, split left to right by source.
    @ViewBuilder
    private func bar(_ row: BuildRecordSummary.Row) -> some View {
        let largest = summary.largestRowTotal
        if row.isRecorded && largest > 0 {
            GeometryReader { geometry in
                let scale = geometry.size.width / CGFloat(largest)
                HStack(spacing: 0) {
                    Color.secondary.frame(width: CGFloat(row.unattributed) * scale)
                    Color.accentColor.frame(width: CGFloat(row.tokens) * scale)
                    Color.orange.frame(width: CGFloat(row.sandpaper) * scale)
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
        } else {
            Color.clear.frame(height: 6)
        }
    }

    /// The whole build by source, each behind a dot in its bar colour. One concatenated `Text`, so it wraps.
    private var footer: some View {
        let openedAtKnown = summary.openedAt != nil
        var text = Text(verbatim: "")
        for (index, amount) in summary.totals.enumerated() {
            if index > 0 { text = text + Text(verbatim: "   ") }
            let name = Self.sourceName(amount.source, openedAtKnown: openedAtKnown, l: l)
            text = text
                + Text(Image(systemName: "circle.fill")).font(.system(size: 6)).foregroundStyle(Self.color(amount.source))
                + Text(verbatim: "\u{00A0}\(name)\u{00A0}\(TokenFormatter.compact(amount.value))")
        }
        return text
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(Self.breakdownText(summary.totals, openedAtKnown: openedAtKnown, l: l))
    }

    /// A numeric date in `locale` and the calendar's time zone: with the year ("2026. 11. 27.") or month and day only.
    static func dateText(_ date: Date, year: Bool, locale: Locale, calendar: Calendar) -> String {
        var style = year ? Date.FormatStyle(date: .numeric, time: .omitted)
                         : Date.FormatStyle().month(.defaultDigits).day(.defaultDigits)
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// The line under the title (spec 5.4).
    static func headerText(_ summary: BuildRecordSummary, l: L, locale: Locale, now: Date, calendar: Calendar) -> String {
        func date(_ date: Date) -> String { dateText(date, year: true, locale: locale, calendar: calendar) }
        var opening = summary.openedAt.map { l.buildRecordOpened(date($0)) }
            ?? l.buildRecordFromMid(gradeLabel(summary.firstRecordedSpeciesID))
        switch summary.end {
        case .completed(let endedAt?): opening += " → " + l.buildRecordCompleted(date(endedAt))
        case .stopped(let endedAt?): opening += " → " + l.buildRecordStopped(date(endedAt))
        case .raising, .completed(.none), .stopped(.none): break
        }
        var parts = [opening]
        switch summary.duration(now: now, calendar: calendar) {
        case .sameDay: parts.append(l.buildRecordSameDay)
        case .days(let n): parts.append(l.buildRecordDays(n))
        case .dayNumber(let n): parts.append(l.buildRecordDayNumber(n))
        case nil: break
        }
        let total = TokenFormatter.compact(summary.total)
        parts.append(summary.end == .raising ? l.buildRecordSoFar(total) : l.buildRecordTotal(total))
        return parts.joined(separator: " · ")
    }

    /// "Alpha 100 · 스펀지 사포 50": a grade's tooltip (spec 5.6). The footer uses the same names and order.
    static func breakdownText(_ amounts: [BuildRecordSummary.Amount], openedAtKnown: Bool, l: L) -> String {
        amounts.map { "\(sourceName($0.source, openedAtKnown: openedAtKnown, l: l)) \(TokenFormatter.compact($0.value))" }
            .joined(separator: " · ")
    }

    private static func gradeLabel(_ speciesID: Int) -> String { GunplaID.decode(speciesID)?.grade.label ?? "" }

    private static func sourceName(_ source: BuildRecordSummary.Source, openedAtKnown: Bool, l: L) -> String {
        switch source {
        case .provider(_, let name): name
        case .sandpaper: l.itemName(.rareCandy)
        case .unattributed: openedAtKnown ? l.buildRecordBeforeUnboxing : l.buildRecordBeforeRecord
        }
    }

    /// The bar's segment colour for a source.
    private static func color(_ source: BuildRecordSummary.Source) -> Color {
        switch source {
        case .provider: .accentColor
        case .sandpaper: .orange
        case .unattributed: .secondary
        }
    }
}
