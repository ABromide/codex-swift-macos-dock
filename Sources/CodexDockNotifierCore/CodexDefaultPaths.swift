import Foundation

public enum CodexDefaultPaths {
    public static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static var sessionsDirectory: URL {
        homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public static var sessionIndexFile: URL {
        homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("session_index.jsonl")
    }

    public static var codexStateDatabase: URL {
        homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("state_5.sqlite")
    }

    public static var applicationSupportDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("CodexDockNotifier", isDirectory: true)
    }

    public static var stateFile: URL {
        applicationSupportDirectory.appendingPathComponent("state.json")
    }
}
