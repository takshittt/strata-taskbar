import os

/// NSLog's message is redacted as `<private>` in `log stream`, so log through os.Logger marked public.
enum Log {
    private static let logger = Logger(subsystem: "local.strata.Strata", category: "app")

    static func info(_ message: String) {
        logger.log("Strata: \(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("Strata: \(message, privacy: .public)")
    }
}
