import SwiftUI
import AppKit

/// The transfers history: a scrollable Card, rows separated by a small gap
/// (not dividers) with hover highlighting — the same list shape as Nearby
/// devices. Fills up to `maxHeight` and only scrolls once it would exceed it.
struct TransfersList: View {
    let transfers: [ActiveTransfer]
    let onClear: () -> Void
    let onCancel: (ActiveTransfer) -> Void
    /// A fixed ceiling rather than one measured from the window. Deriving it
    /// from the space left over needed a root `GeometryReader`, which left the
    /// window without a defined ideal height and so defeated
    /// `.windowResizability(.contentSize)` entirely.
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
