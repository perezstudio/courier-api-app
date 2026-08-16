import Foundation
import Security

/// Storage for secret variable and auth values.
///
/// Secrets never enter Core Data: the store is an unencrypted SQLite file in
/// Application Support, and API tokens sitting there in plaintext is a bad
/// posture regardless of whether anything syncs. See REQUIREMENTS.md §6.
protocol SecretStore: Sendable {
    func value(for id: UUID) throws -> String?
    func set(_ value: String, for id: UUID) throws
    func delete(for id: UUID) throws
    /// Every id with a stored secret, for the orphan sweep.
    func allIdentifiers() throws -> Set<UUID>
}

// MARK: - Keychain

/// Keychain-backed implementation.
///
/// Items are stored **without** `kSecAttrSynchronizable`, so they never leave
/// this Mac. That is deliberate: a secret set here should not propagate
/// anywhere, and Courier has no sync to propagate it to.
struct KeychainSecretStore: SecretStore {

    enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)
        case dataCorrupted

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let message = SecCopyErrorMessageString(status, nil) as String?
                return "Keychain error \(status): \(message ?? "unknown")"
            case .dataCorrupted:
                return "The stored secret could not be decoded."
            }
        }
    }

    let service: String

    init(service: String = "com.perezstudio.Courier.secrets") {
        self.service = service
    }

    func value(for id: UUID) throws -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataCorrupted
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func set(_ value: String, for id: UUID) throws {
        let data = Data(value.utf8)
        let query = baseQuery(for: id)

        // Try update first; SecItemAdd on an existing account returns
        // errSecDuplicateItem rather than overwriting.
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    func delete(for id: UUID) throws {
        let status = SecItemDelete(baseQuery(for: id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func allIdentifiers() throws -> Set<UUID> {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        query[kSecReturnData as String] = false

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        switch status {
        case errSecSuccess:
            guard let entries = items as? [[String: Any]] else { return [] }
            let ids = entries.compactMap { entry -> UUID? in
                guard let account = entry[kSecAttrAccount as String] as? String else { return nil }
                return UUID(uuidString: account)
            }
            return Set(ids)
        case errSecItemNotFound:
            return []
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func baseQuery(for id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }
}

// MARK: - In-memory

/// Test double. Unit tests must not write to the developer's real Keychain.
final class InMemorySecretStore: SecretStore, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [UUID: String] = [:]

    init() {}

    func value(for id: UUID) throws -> String? {
        lock.withLock { storage[id] }
    }

    func set(_ value: String, for id: UUID) throws {
        lock.withLock { storage[id] = value }
    }

    func delete(for id: UUID) throws {
        _ = lock.withLock { storage.removeValue(forKey: id) }
    }

    func allIdentifiers() throws -> Set<UUID> {
        lock.withLock { Set(storage.keys) }
    }
}
