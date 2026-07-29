import Foundation

/// Everything QShare persists, and the migrations between older shapes of it.
///
/// Split out of `AppModel` so the view model states *what* it wants remembered
/// and this states *how*. Keys live here and nowhere else.
struct Preferences {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key {
        static let downloadDirectory = "downloadDirectoryPath"
        static let startVisible = "startVisible"
        static let appearance = "appearance"
        static let controlAPIEnabled = "controlAPIEnabled"
        static let knownDevices = "knownDevices"
        static let recentFiles = "recentFiles"
        // Earlier shapes of the known-devices list, migrated on load.
        static let legacyKnownNames = "knownDeviceNames"
        static let legacyTrustedNames = "trustedDeviceNames"
    }

    // MARK: Settings

    var downloadDirectory: URL? {
        get { defaults.string(forKey: Key.downloadDirectory).map { URL(fileURLWithPath: $0) } }
        nonmutating set { defaults.set(newValue?.path, forKey: Key.downloadDirectory) }
    }

    var startVisible: Bool {
        get { defaults.bool(forKey: Key.startVisible) }
        nonmutating set { defaults.set(newValue, forKey: Key.startVisible) }
    }

    var controlAPIEnabled: Bool {
        get { defaults.bool(forKey: Key.controlAPIEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.controlAPIEnabled) }
    }

    var appearance: AppAppearance {
        get {
            defaults.string(forKey: Key.appearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    // MARK: Known devices

    /// Loads the list, migrating the two earlier storage shapes.
    ///
    /// Those were plain arrays of names with no per-device choice, so everything
    /// migrated arrives with auto-accept **off**. An upgrade must never switch
    /// it on for someone.
    func loadKnownDevices() -> [KnownDevice] {
        if let data = defaults.data(forKey: Key.knownDevices),
           let decoded = try? JSONDecoder().decode([KnownDevice].self, from: data) {
            return decoded
        }
        var migrated: [String] = defaults.stringArray(forKey: Key.legacyKnownNames) ?? []
        migrated += defaults.stringArray(forKey: Key.legacyTrustedNames) ?? []
        defaults.removeObject(forKey: Key.legacyKnownNames)
        defaults.removeObject(forKey: Key.legacyTrustedNames)
        return Array(Set(migrated)).sorted().map { KnownDevice(name: $0, autoAccept: false) }
    }

    func save(knownDevices: [KnownDevice]) {
        guard let data = try? JSONEncoder().encode(knownDevices) else { return }
        defaults.set(data, forKey: Key.knownDevices)
    }

    // MARK: Recent files

    func loadRecentFiles() -> [RecentFile] {
        guard let data = defaults.data(forKey: Key.recentFiles),
              let decoded = try? JSONDecoder().decode([RecentFile].self, from: data) else {
            return []
        }
        return decoded
    }

    func save(recentFiles: [RecentFile]) {
        guard let data = try? JSONEncoder().encode(recentFiles) else { return }
        defaults.set(data, forKey: Key.recentFiles)
    }
}
