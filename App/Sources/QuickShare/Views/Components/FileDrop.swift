import Foundation
import UniformTypeIdentifiers
import SwiftUI

/// Resolve dropped item providers into file URLs, then deliver on the main queue.
///
/// `loadObject` completions fire concurrently on arbitrary queues, so the
/// results are written into pre-allocated slots under a lock rather than
/// appended. Slot indexing also keeps the user's drop order, which racing
/// appends did not.
func loadDroppedFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let lock = NSLock()
    var slots = [URL?](repeating: nil, count: providers.count)
    let group = DispatchGroup()
    for (index, provider) in providers.enumerated() {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url, url.isFileURL {
                lock.lock()
                slots[index] = url
                lock.unlock()
            }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(slots.compactMap { $0 }) }
}
