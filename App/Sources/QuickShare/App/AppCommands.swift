import SwiftUI
import AppKit

/// Clears out the standard commands this app can't act on.
///
/// Split into its own type because `CommandsBuilder`, like `ViewBuilder`, caps
/// how many children one block may have.
private struct InertDefaultsRemoved: Commands {
    var body: some Commands {
        // Nothing in this app accepts text, so the entire Edit menu was dead.
        CommandGroup(replacing: .undoRedo) {}
        CommandGroup(replacing: .pasteboard) {}
        CommandGroup(replacing: .textEditing) {}
        // Note: no `.textFormatting` replacement. Replacing it with an empty
        // group *creates* an empty Format menu that wasn't there before —
        // AppDelegate prunes what the system insists on instead.
        CommandGroup(replacing: .toolbar) {}
        CommandGroup(replacing: .help) {}
        // No documents, so New and Open would do nothing.
        CommandGroup(replacing: .newItem) {}
    }
}

/// The menu bar.
///
/// SwiftUI's defaults assume a document app with text editing, a toolbar and a
/// sidebar. This app has none of those, so most of Edit and View were inert
/// commands. They're removed rather than left to look broken, and what remains
/// is only what this app can actually do.
struct AppCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {

        InertDefaultsRemoved()

        // MARK: QShare

        CommandGroup(after: .appInfo) {
            Button("Build Info…") { model.showingBuildInfo = true }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }

        // MARK: File

        CommandGroup(replacing: .saveItem) {
            Button("Open Downloads Folder") { model.openDownloadsFolder() }
                .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            // Recent files, newest first. Entries whose file has since been
            // moved or deleted are shown disabled rather than silently failing.
            if model.recentFiles.isEmpty {
                Text("No Recent Files")
            } else {
                ForEach(model.recentFiles) { file in
                    Button(file.name) { model.openRecentFile(file) }
                        .disabled(!file.stillExists)
                }
                Divider()
                Button("Clear Menu") { model.clearRecentFiles() }
            }
        }

        // MARK: View
        //
        // Replaces the sidebar group, which lives in the View menu and did
        // nothing here.

        CommandGroup(replacing: .sidebar) {
            Button("Send") { model.mode = .send }
                .keyboardShortcut("1", modifiers: .command)
            Button("Receive") { model.mode = .receive }
                .keyboardShortcut("2", modifiers: .command)

            Divider()

            Button(model.wantsVisible ? "Stop Being Visible" : "Be Visible to Nearby Devices") {
                model.toggleVisibility()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Divider()

            Button("Clear Completed Transfers") { model.clearFinishedTransfers() }
                .disabled(!model.transfers.contains { $0.phase.isTerminal })
        }

        // MARK: Window
        //
        // Ours rather than macOS's tiling: this window has a hard width cap, so
        // "Left Half" would only ever produce a clamped window in roughly the
        // right place. These keep the app's width and grow it to full height.

        CommandGroup(after: .windowSize) {
            Divider()
            Button("Snap Left") { WindowPlacement.snap(to: .left) }
                .keyboardShortcut(.leftArrow, modifiers: [.control, .option])
            Button("Snap Right") { WindowPlacement.snap(to: .right) }
                .keyboardShortcut(.rightArrow, modifiers: [.control, .option])
            Button("Center Window") { WindowPlacement.center() }
        }
    }
}
