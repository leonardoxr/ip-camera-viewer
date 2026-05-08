import Foundation
import Security

enum CameraCredentialStore {
    private static let service = "IPCameraViewer.CameraCredentials.v2"
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cachedPasswords: [Camera.ID: String] = [:]

    static func password(for cameraID: Camera.ID) -> String {
        lock.lock()
        if let cachedPassword = cachedPasswords[cameraID] {
            lock.unlock()
            return cachedPassword
        }
        lock.unlock()

        var query = baseQuery(for: cameraID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return ""
        }

        cache(password: password, for: cameraID)
        return password
    }

    @discardableResult
    static func save(password: String, for cameraID: Camera.ID) -> Bool {
        guard !password.isEmpty else {
            deletePassword(for: cameraID)
            return true
        }

        let data = Data(password.utf8)
        let query = baseQuery(for: cameraID)
        let attributes = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            cache(password: password, for: cameraID)
            return true
        }

        if status != errSecItemNotFound {
            SecItemDelete(query as CFDictionary)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        if addStatus == errSecSuccess {
            cache(password: password, for: cameraID)
            return true
        }

        AppLoggers.cameras.error("Unable to save camera password in Keychain: \(addStatus, privacy: .public)")
        return false
    }

    static func deletePassword(for cameraID: Camera.ID) {
        lock.lock()
        cachedPasswords.removeValue(forKey: cameraID)
        lock.unlock()

        let status = SecItemDelete(baseQuery(for: cameraID) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLoggers.cameras.error("Unable to delete camera password from Keychain: \(status, privacy: .public)")
        }
    }

    private static func cache(password: String, for cameraID: Camera.ID) {
        lock.lock()
        cachedPasswords[cameraID] = password
        lock.unlock()
    }

    private static func baseQuery(for cameraID: Camera.ID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cameraID.uuidString
        ]
    }
}
