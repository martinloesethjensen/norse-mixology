import os

/// App-wide `os.Logger` categories — use these instead of `print`.
public enum AppLog {
    private static let subsystem = "dev.martinloeseth.NorseMixology"

    /// Bundled taxonomy / recipe catalog loading.
    public static let catalog = Logger(subsystem: subsystem, category: "catalog")
}
