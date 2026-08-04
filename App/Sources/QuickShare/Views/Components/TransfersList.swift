import SwiftUI
import AppKit

/// Height of the fixed controls above the transfers panel, so the panel's cap
/// can be "whatever is actually left" rather than a guess.
struct ControlsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The transfers history: a scrollable Card, rows separated by a small gap
/// (not dividers) with hover highlighting — the same list shape as Nearby
/// devices. Fills up to `maxHeight` and only scrolls once it would exceed it.
struct TransfersList: View {
    let transfers: [ActiveTransfer]
    let onClear: () -> Void
    let onCancel: (ActiveTransfer) -> Void
    /// Ceiling from the parent, measured from what's actually left in the
    /// window. The panel fills up to this, then scrolls.
    var maxHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title: "Transfers") {
                Button("Clear", action: onClear)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.orange)
            }

            Card(padding: Theme.Space.xs, maxHeight: maxHeight) {
                ElementList(items: transfers) { t in
                    TransferRow(transfer: t) { onCancel(t) }
                }
            }
        }
    }
}
