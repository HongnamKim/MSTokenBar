import SwiftUI

/// What the pre-order pick's bottom panel shows: the modes of a tapped multi-mode cell, or one machine to confirm.
enum PreorderChoice: Equatable {
    case modes([Int])
    case machine(Int)
}

/// Bottom panel of the pre-order pick: the mode list (§7.4) or the confirm row (§7.5).
/// It overlays the bottom of the hangar, so the grid does not relayout. Paying happens only from [Pre-order].
@MainActor
struct PreorderPickPanel: View {
    let store: CompanionStore
    let choice: PreorderChoice
    let onChooseMode: (Int) -> Void
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        Group {
            switch choice {
            case .modes(let ids): modeList(ids)
            case .machine(let id): confirmRow(id)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    /// One row per mode: name, rarity, price. A finished or building mode shows why instead of a price.
    private func modeList(_ ids: [Int]) -> some View {
        let l = store.l
        let statuses = store.preorderPickStatuses   // one collection snapshot for every row
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(ids, id: \.self) { id in
                if let machine = store.catalog.machine(id: id) {
                    let status = statuses[id] ?? .complete
                    Button { onChooseMode(id) } label: {
                        HStack(spacing: 6) {
                            Text(store.machineName(id)).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                            Text(l.rarityLabel(machine.rarity)).foregroundStyle(.secondary).fixedSize()
                            Spacer(minLength: 4)
                            Group {
                                switch status {
                                case .available: Text(TokenFormatter.compact(store.preorderPrice(machine)))
                                case .complete: Text(l.preorderCompleteLabel)
                                case .building: Text(l.preorderBuildingLabel)
                                }
                            }
                            .monospacedDigit().fixedSize()
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(status != .available)
                    .opacity(status == .available ? 1 : 0.45)
                }
            }
            HStack {
                Spacer()
                Button(l.cancel) { onCancel() }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    /// "MS-07B Gouf · Uncommon", the odds, then the price with [Pre-order] [Cancel]. Only the name truncates.
    @ViewBuilder private func confirmRow(_ id: Int) -> some View {
        let l = store.l
        if let machine = store.catalog.machine(id: id) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(machine.modelNumber).fixedSize()
                    Text(store.machineName(id)).lineLimit(1).truncationMode(.middle)
                    Text("· \(l.rarityLabel(machine.rarity))").fixedSize()
                }
                .font(.callout.weight(.semibold))
                Text(l.preorderOddsLine)
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(TokenFormatter.compact(store.preorderPrice(machine)))
                        .font(.callout.weight(.semibold)).monospacedDigit()
                    Spacer()
                    if store.canBuyPreorder(id) {
                        Button(l.preorderShort) { onConfirm(id) }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    } else {
                        Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Button(l.cancel) { onCancel() }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
        }
    }
}
