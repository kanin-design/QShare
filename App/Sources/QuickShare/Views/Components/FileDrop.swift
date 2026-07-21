import Foundation
import UniformTypeIdentifiers
import SwiftUI

/// Resolve dropped item providers into file URLs, then deliver on the main queue.
func loadDroppedFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls: [URL] = []
    let group = DispatchGroup()
    for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url, url.isFileURL { urls.append(url) }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}
