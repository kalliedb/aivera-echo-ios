import Foundation

/// iOS Data Protection wrapper. Applies an `NSFileProtection` class to a file
/// or directory so contents are encrypted by iOS at rest (Secure-Enclave-backed
/// AES-256 derived from the device passcode).
///
/// The chosen level — `completeUntilFirstUserAuthentication` — gives full
/// encryption between device reboot and the user's first unlock that boot,
/// then keeps the file accessible while the app needs to schedule notifications
/// or run background work. This is iOS's default for app sandboxes and the
/// recommended level for productivity apps; bumping to `complete` would block
/// background reminder fires when the screen is locked.
enum FileProtection {

    static let level: FileProtectionType = .completeUntilFirstUserAuthentication

    /// Apply the protection class to the file at `url`. No-op if the file
    /// doesn't exist (some sidecars like `.wal` are created lazily by SQLite).
    @discardableResult
    static func apply(to url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.setAttributes(
                [.protectionKey: level],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            print("FileProtection.apply failed for \(url.lastPathComponent): \(error)")
            return false
        }
    }
}
