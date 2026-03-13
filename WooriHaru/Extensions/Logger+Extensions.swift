import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.woori-haru"

    static let store = Logger(subsystem: subsystem, category: "Store")
}
