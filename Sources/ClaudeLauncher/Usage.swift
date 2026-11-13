import Foundation
import Security

/// how much of the plan's limits is used, as claude code's /usage shows it: the five-hour session and
/// the week, each as a percentage and when it resets. read with the sign-in claude code keeps in the
/// keychain ("Claude Code-credentials"); macOS asks once before handing it over. the sign-in is only
/// read, never refreshed, so claude code's own stays valid: when it has expired nothing is shown until
/// claude refreshes it.
struct Usage: Equatable, Sendable {
    struct Window: Equatable, Sendable {
        let percent: Double
        let resetsAt: Date?
    }

    let session: Window?
    let week: Window?

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// the answer, or nil when there is no sign-in, it expired, or the request fails
    static func fetch() async -> Usage? {
        guard let token = accessToken() else { return nil }
        var request = URLRequest(url: endpoint, timeoutInterval: 8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-launcher", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    static func parse(_ data: Data) -> Usage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func window(_ key: String) -> Window? {
            guard let w = json[key] as? [String: Any], let percent = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            let reset = (w["resets_at"] as? String).flatMap { dates.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return Window(percent: percent, resetsAt: reset)
        }
        let usage = Usage(session: window("five_hour"), week: window("seven_day"))
        return usage.session == nil && usage.week == nil ? nil : usage
    }

    /// claude code's access token, while it is still valid
    private static func accessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }
        if let expires = (oauth["expiresAt"] as? NSNumber)?.doubleValue, expires / 1000 < Date().timeIntervalSince1970 + 30 {
            return nil
        }
        return token
    }
}
