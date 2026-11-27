import SwiftUI

/// Series box list — a screen inside the Shop tab (no sheet; see `ShopView`). Pick a series, then confirm
/// inline. A series with nothing left to build is dimmed and disabled.
@MainActor
struct SeriesBoxListView: View {
    let store: CompanionStore
    let onBack: () -> Void
    let onBought: () -> Void
    @State private var selected: String?

    var body: some View {
        let l = store.l
        let counts = store.seriesBoxRemainingCounts
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onBack) {
                    Label(l.back, systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(l.seriesBoxTitle).font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.catalog.series.sorted { $0.order < $1.order }, id: \.id) { series in
                        row(series.id, remaining: counts[series.id] ?? 0,
                            enabled: isEnabled(series.id, counts: counts))
                    }
                }
                .reservesScrollerLane()
            }
            if let id = selected, isEnabled(id, counts: counts) {
                ReplaceBoxConfirmRow(
                    store: store,
                    prompt: l.seriesBoxConfirm(store.displayName, store.seriesName(id)),
                    onCommit: { if store.buySeriesBox(id) { onBought() } },
                    onCancel: { selected = nil })
                .id(id)
            }
        }
    }

    /// Same rule as `canBuySeriesBox`, from counts read once per body; commit still goes through the store.
    private func isEnabled(_ id: String, counts: [String: Int]) -> Bool {
        store.hasActive && (counts[id] ?? 0) > 0 && store.availableTokens >= store.seriesBoxPrice(id)
    }

    private func row(_ id: String, remaining: Int, enabled: Bool) -> some View {
        let isSelected = selected == id
        return Button { selected = id } label: {
            HStack(spacing: 8) {
                Text(store.seriesName(id))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(store.l.seriesBoxRemaining(remaining))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    .fixedSize()
                Text(TokenFormatter.compact(store.seriesBoxPrice(id)))
                    .font(.system(size: 11, weight: .bold)).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(remaining == 0 ? 0.5 : 1)
    }
}
