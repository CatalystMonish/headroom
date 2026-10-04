import Foundation
import Security

// Where the OAuth token comes from. A pasted token wins; otherwise (by default)
// Claude Code's own login is read from the Keychain via /usr/bin/security, so
// macOS asks once. A pasted token lives in Headroom's own Keychain item, never
// in a plain file.
enum TokenStore {
	private static let service = "io.github.catalystmonish.headroom"
	private static let account = "oauth-token"

	static var useClaudeCode: Bool {
		get { UserDefaults.standard.object(forKey: "useClaudeCode") as? Bool ?? true }
		set { UserDefaults.standard.set(newValue, forKey: "useClaudeCode") }
	}

	static func token() -> String? {
		if let t = pasted(), !t.isEmpty { return t }
		return useClaudeCode ? claudeCodeToken() : nil
	}

	// MARK: pasted token (Headroom's own Keychain item)
	private static var query: [String: Any] {
		[kSecClass as String: kSecClassGenericPassword,
		 kSecAttrService as String: service,
		 kSecAttrAccount as String: account]
	}

	static func pasted() -> String? {
		var q = query
		q[kSecReturnData as String] = true
		q[kSecMatchLimit as String] = kSecMatchLimitOne
		var out: CFTypeRef?
		guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
		return String(data: data, encoding: .utf8)
	}

	static func setPasted(_ token: String) {
		SecItemDelete(query as CFDictionary)
		let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !t.isEmpty else { return }
		var q = query
		q[kSecValueData as String] = Data(t.utf8)
		SecItemAdd(q as CFDictionary, nil)
	}

	// MARK: Claude Code's login
	private static func claudeCodeToken() -> String? {
		let p = Process()
		p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
		p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
		let pipe = Pipe()
		p.standardOutput = pipe
		p.standardError = FileHandle.nullDevice
		guard (try? p.run()) != nil else { return nil }
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		p.waitUntilExit()
		guard p.terminationStatus == 0,
		      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
		      let oauth = root["claudeAiOauth"] as? [String: Any],
		      let t = oauth["accessToken"] as? String, !t.isEmpty else { return nil }
		return t
	}
}
