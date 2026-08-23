import SwiftUI

/// The coat shop: what a colour costs, what you can afford, and what you own.
struct MenuShopTab: View {
    let model: AppModel
    let settings: Settings
    let onSettingsChanged: () -> Void

    /// The coat whose Buy button has been pressed once. A purchase is the only
    /// thing in this menu a second tap cannot undo, so it takes two.
    @State private var pendingCoatID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            balanceSection
            Divider()
            coatsSection
        }
    }

    // MARK: - Balance

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("To spend").font(.headline)
                Spacer()
                Text(TokenFormatter.compact(model.balance))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
            }
            Text(model.spent > 0
                 ? "Every token you have ever spent, less the \(TokenFormatter.compact(model.spent)) already spent here."
                 : "Every token you have ever spent. Keep working and it keeps growing.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Coats

    private var coatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coats").font(.headline)
            ForEach(CoatShop.all) { coat in
                coatRow(coat)
            }
        }
    }

    private func coatRow(_ coat: Coat) -> some View {
        let owned = model.owns(coat)
        let selected = settings.coatID == coat.id
        return HStack(spacing: 10) {
            swatch(coat)
            VStack(alignment: .leading, spacing: 1) {
                Text(coat.name).font(.callout)
                if !owned {
                    Text(TokenFormatter.compact(coat.price))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            control(for: coat, owned: owned, selected: selected)
        }
        .contentShape(Rectangle())
        .onTapGesture { if owned { wear(coat) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(owned ? coat.name : "\(coat.name), \(TokenFormatter.compact(coat.price)) tokens")
    }

    private func swatch(_ coat: Coat) -> some View {
        Circle()
            .fill(coat.bodyColor)
            .frame(width: 22, height: 22)
            .overlay(Circle().stroke(.secondary.opacity(0.5), lineWidth: 1))
    }

    @ViewBuilder
    private func control(for coat: Coat, owned: Bool, selected: Bool) -> some View {
        if owned {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(selected ? Color.accentColor : .secondary)
        } else if model.canAfford(coat) {
            Button(pendingCoatID == coat.id ? "Confirm" : "Buy") { confirmOrBuy(coat) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        } else {
            Image(systemName: "lock.fill").foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func confirmOrBuy(_ coat: Coat) {
        guard pendingCoatID == coat.id else {
            pendingCoatID = coat.id
            return
        }
        model.buy(coat)
        pendingCoatID = nil
        wear(coat)
    }

    /// Buying is also choosing: nobody spends 25B on a coat to then go and select it.
    private func wear(_ coat: Coat) {
        settings.coatID = coat.id
        onSettingsChanged()
    }
}
