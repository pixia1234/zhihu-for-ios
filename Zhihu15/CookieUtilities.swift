import Foundation
import WebKit

enum ZhihuCookieUtilities {
    static func values(from cookies: [HTTPCookie], for url: URL) -> [String: String] {
        var result: [String: String] = [:]
        for cookie in cookies where cookie.value.isEmpty == false && applies(cookie, to: url) {
            result[cookie.name] = cookie.value
        }
        return result
    }

    static func makeCookies(from values: [String: String], for url: URL) -> [HTTPCookie] {
        values.compactMap { name, value in
            var properties: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: ".zhihu.com",
                .path: "/",
                .originURL: url
            ]
            if url.scheme?.lowercased() == "https" { properties[.secure] = "TRUE" }
            return HTTPCookie(properties: properties)
        }
    }

    static func json(from values: [String: String]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func values(from json: String) -> [String: String]? {
        guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var values: [String: String] = [:]
        for (key, value) in object { guard let string = value as? String else { continue }; values[key] = string }
        return values
    }

    static func install(_ cookies: [HTTPCookie], in store: WKHTTPCookieStore, completion: @escaping () -> Void) {
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main, execute: completion)
    }

    private static func applies(_ cookie: HTTPCookie, to url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return (host == domain || host.hasSuffix(".\(domain)")) && (!cookie.isSecure || url.scheme?.lowercased() == "https")
    }
}
