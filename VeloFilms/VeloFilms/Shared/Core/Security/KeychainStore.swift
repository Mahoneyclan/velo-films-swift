// KeychainStore.swift
// Minimal Keychain wrapper for small secrets. Used by StravaAuth to hold the Strava sign-in tokens.

import Foundation
import Security
import os

/// Saves, reads and deletes small secrets as Keychain generic-password items.
///
/// Security: items use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so on iOS/iPadOS they are encrypted
/// at rest, never sync to iCloud Keychain or move to another device through a backup, and stay readable after the
/// first unlock so a token refresh can run while the screen is locked. On macOS items go in the user's login
/// keychain, which is encrypted and restricts access to this app; the accessibility value is not enforced there.
/// The macOS data-protection keychain is not used because it needs a keychain-access-groups entitlement that
/// this unsandboxed build doesn't have (writes fail with -34018). Revisit when the App Sandbox is enabled.
///
/// Calls are synchronous and quick; callers run on the main actor.
enum KeychainStore {
    /// Service name shared by every item this app stores. Permanent: changing it orphans saved items.
    private static let service = "mahoneyclan.VeloFilms"
    private static let log = Logger(subsystem: "com.velofilms", category: "KeychainStore")

    /// Reads the string stored under `account`.
    /// - Parameter account: The item's key, e.g. `"stravaAccessToken"`.
    /// - Returns: The stored string, or `nil` if there is no item or it can't be read.
    static func string(for account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound { log.error("Keychain read failed: \(status, privacy: .public)") }
            return nil
        }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores `value` under `account`, replacing any existing item. Passing `nil` deletes the item.
    /// - Parameters:
    ///   - value: The string to store, or `nil` to delete.
    ///   - account: The item's key, e.g. `"stravaAccessToken"`.
    /// - Returns: `true` if the Keychain now matches the request (a delete of a missing item counts as success).
    ///   On `false` after a write, the previous value (if any) is still stored.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        guard let value else {
            let deleteStatus = SecItemDelete(baseQuery(account) as CFDictionary)
            let ok = deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound
            if !ok { log.error("Keychain delete failed: \(deleteStatus, privacy: .public)") }
            return ok
        }
        // Security: update in place, adding only if no item exists, so a failed write never leaves the user
        // with no token at all (deleting first and then failing to add would sign them out).
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = baseQuery(account).merging(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess { log.error("Keychain write failed: \(status, privacy: .public)") }
        return status == errSecSuccess
    }

    /// The attributes that identify one item: class, service and account.
    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
