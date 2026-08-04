import SwiftUI
import AppKit

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
            SectionHeader(title: "Transfers", trailing: AnyView(
                Button("Clear", action: onClear)
                    // `.glass` (not `.glassProminent`) resolves its own label
                    // contrast from whatever's behind it — reliable on a
                    // Card's glassSurface, but this sits directly on the
                    // plain window background, where in Light mode a
                    // `.glass` + tint came out nearly invisible. `.glassProminent`
                    // always renders a solid, guaranteed-legible fill.
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .tint(Theme.orange)
            ))

            Card(padding: Theme.Space.xs, maxHeight: maxHeight) {
                ElementList(items: transfers) { t in
                    TransferRow(transfer: t) { onCancel(t) }
                }
            }
        }
    }
}
