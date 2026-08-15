import Foundation
import Security
import CryptoKit

struct ZhihuProfile: Codable, Equatable {
    let id: String
    let name: String
    let urlToken: String?
    let avatarURL: URL?
    let headline: String?
}

struct ZhihuAccountSession: Codable, Equatable {
    var cookies: [String: String]
    var userAgent: String
    var profile: ZhihuProfile?

    var isLoggedIn: Bool {
        cookies["d_c0"]?.isEmpty == false || cookies["z_c0"]?.isEmpty == false
    }
}

struct ZhihuAccountSummary: Equatable {
    let id: String
    let name: String
    let avatarURL: URL?
}

private struct ZhihuAccountVault: Codable {
    var currentID: String?
    var accounts: [String: ZhihuAccountSession]
}

final class ZhihuAccountStore {
    static let shared = ZhihuAccountStore()

    // Keep the Keychain namespace aligned with the new bundle identifier so
    // the new build starts with a clean account container instead of reusing
    // credentials left by the previous package.
    private let service = "com.pixia.zhihu15.client.account"
    private let account = "current"
    private let lock = NSLock()

    func load() -> ZhihuAccountSession? {
        lock.lock()
        defer { lock.unlock() }
        let vault = loadVaultUnlocked()
        guard let id = vault.currentID else { return nil }
        return vault.accounts[id]
    }

    func save(_ session: ZhihuAccountSession) throws {
        lock.lock()
        defer { lock.unlock() }
        var vault = loadVaultUnlocked()
        let id = session.profile?.id ?? vault.currentID ?? UUID().uuidString
        vault.accounts[id] = session
        vault.currentID = id
        try saveVaultUnlocked(vault)
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        var vault = loadVaultUnlocked()
        if let id = vault.currentID { vault.accounts.removeValue(forKey: id) }
        vault.currentID = vault.accounts.keys.sorted().first
        try saveVaultUnlocked(vault)
    }

    func listAccounts() -> [ZhihuAccountSummary] {
        lock.lock()
        defer { lock.unlock() }
        return loadVaultUnlocked().accounts.map { id, session in
            ZhihuAccountSummary(id: id, name: session.profile?.name ?? "知乎账号", avatarURL: session.profile?.avatarURL)
        }.sorted { $0.name < $1.name }
    }

    func switchAccount(to id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var vault = loadVaultUnlocked()
        guard vault.accounts[id] != nil else { throw ZhihuSessionError.accountNotFound }
        vault.currentID = id
        try saveVaultUnlocked(vault)
    }

    func deleteAccount(_ id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var vault = loadVaultUnlocked()
        guard vault.accounts[id] != nil else { throw ZhihuSessionError.accountNotFound }
        vault.accounts.removeValue(forKey: id)
        if vault.currentID == id { vault.currentID = vault.accounts.keys.sorted().first }
        try saveVaultUnlocked(vault)
    }

    private func loadVaultUnlocked() -> ZhihuAccountVault {
        guard let data = keychainDataUnlocked() else { return ZhihuAccountVault(currentID: nil, accounts: [:]) }
        if let vault = try? JSONDecoder().decode(ZhihuAccountVault.self, from: data) { return vault }
        if let session = try? JSONDecoder().decode(ZhihuAccountSession.self, from: data) {
            let id = session.profile?.id ?? UUID().uuidString
            return ZhihuAccountVault(currentID: id, accounts: [id: session])
        }
        return ZhihuAccountVault(currentID: nil, accounts: [:])
    }

    private func saveVaultUnlocked(_ vault: ZhihuAccountVault) throws {
        let data = try JSONEncoder().encode(vault)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = base
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw ZhihuSessionError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw ZhihuSessionError.keychain(status)
        }
    }

    private func keychainDataUnlocked() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

enum ZhihuSessionError: LocalizedError {
    case authenticationRequired
    case invalidResponse
    case httpStatus(Int)
    case malformedPayload
    case untrustedURL
    case keychain(OSStatus)
    case accountNotFound

    var errorDescription: String? {
        switch self {
        case .authenticationRequired: return "请先登录知乎"
        case .invalidResponse: return "服务器返回了无效响应"
        case let .httpStatus(code): return "请求失败（HTTP \(code)）"
        case .malformedPayload: return "知乎返回的数据格式无法识别"
        case .untrustedURL: return "请求地址不受信任"
        case let .keychain(status): return "账号安全存储失败（\(status)）"
        case .accountNotFound: return "找不到这个知乎账号"
        }
    }
}

enum ZhihuURLPolicy {
    static func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "zhihu.com" || host.hasSuffix(".zhihu.com")
    }
}

final class ZhihuAPIClient {
    static let shared = ZhihuAPIClient(accountStore: .shared)

    private let accountStore: ZhihuAccountStore
    private let session: URLSession
    private let callbackQueue = DispatchQueue.main

    init(accountStore: ZhihuAccountStore, session: URLSession? = nil) {
        self.accountStore = accountStore
        if let session = session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 32 * 1024 * 1024, diskPath: "zhihu-api")
            self.session = URLSession(configuration: configuration)
        }
    }

    func request(
        _ url: URL,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:],
        requiresLogin: Bool = false,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard ZhihuURLPolicy.allows(url) else {
            callbackQueue.async { completion(.failure(ZhihuSessionError.untrustedURL)) }
            return
        }
        let account = accountStore.load()
        if requiresLogin && account?.isLoggedIn != true {
            callbackQueue.async { completion(.failure(ZhihuSessionError.authenticationRequired)) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(account?.userAgent ?? Self.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("fetch", forHTTPHeaderField: "x-requested-with")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let cookies = account?.cookies, !cookies.isEmpty {
            request.setValue(cookies.keys.sorted().map { "\($0)=\(cookies[$0] ?? "")" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
            if let xsrf = cookies["_xsrf"], !xsrf.isEmpty {
                request.setValue(xsrf, forHTTPHeaderField: "x-xsrftoken")
            }
            ZhihuRequestSigner.apply(to: &request, cookies: cookies, body: body)
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.callbackQueue.async { completion(.failure(error)) }
                return
            }
            guard let http = response as? HTTPURLResponse,
                  let responseURL = http.url,
                  ZhihuURLPolicy.allows(responseURL) else {
                self?.callbackQueue.async { completion(.failure(ZhihuSessionError.invalidResponse)) }
                return
            }
            self?.mergeCookies(from: http)
            guard (200..<300).contains(http.statusCode) else {
                self?.callbackQueue.async { completion(.failure(ZhihuSessionError.httpStatus(http.statusCode))) }
                return
            }
            // Vote/follow mutations may legitimately return HTTP 204 with no
            // body. Treat that as a successful empty response.
            self?.callbackQueue.async { completion(.success(data ?? Data())) }
        }.resume()
    }

    func fetchProfile(completion: @escaping (Result<ZhihuProfile, Error>) -> Void) {
        request(URL(string: "https://www.zhihu.com/api/v4/me")!, requiresLogin: true) { [weak self] result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                do {
                    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = root["id"] as? String,
                          let name = root["name"] as? String else { throw ZhihuSessionError.malformedPayload }
                    let profile = ZhihuProfile(
                        id: id,
                        name: name,
                        urlToken: root["url_token"] as? String ?? root["urlToken"] as? String,
                        avatarURL: (root["avatar_url"] as? String ?? root["avatarUrl"] as? String).flatMap(URL.init(string:)),
                        headline: root["headline"] as? String
                    )
                    if var account = self?.accountStore.load() {
                        account.profile = profile
                        try? self?.accountStore.save(account)
                    }
                    completion(.success(profile))
                } catch { completion(.failure(error)) }
            }
        }
    }

    private func mergeCookies(from response: HTTPURLResponse) {
        guard let url = response.url else { return }
        var fields: [String: String] = [:]
        response.allHeaderFields.forEach { key, value in fields[String(describing: key)] = String(describing: value) }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !cookies.isEmpty, var account = accountStore.load() else { return }
        for cookie in cookies where cookie.domain.lowercased().contains("zhihu.com") {
            if cookie.value.isEmpty || cookie.expiresDate.map({ $0 < Date() }) == true {
                account.cookies.removeValue(forKey: cookie.name)
            } else {
                account.cookies[cookie.name] = cookie.value
            }
        }
        try? accountStore.save(account)
    }

    private static let defaultUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
}

enum ZhihuRequestSigner {
    static func apply(to request: inout URLRequest, cookies: [String: String], body: Data?) {
        guard let url = request.url, let dc0 = cookies["d_c0"], !dc0.isEmpty else { return }
        let version = "101_3_3.0"
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var path = components?.percentEncodedPath ?? url.path
        if path.isEmpty { path = "/" }
        if let query = components?.percentEncodedQuery, !query.isEmpty { path += "?\(query)" }
        let bodyText = body.flatMap { String(data: $0, encoding: .utf8) }
        let source = [version, path, dc0, bodyText].compactMap { $0 }.joined(separator: "+")
        let digest = Insecure.MD5.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        request.setValue(version, forHTTPHeaderField: "x-zse-93")
        request.setValue("2.0_\(ZseV4.encrypt(digest))", forHTTPHeaderField: "x-zse-96")
        request.setValue("fetch", forHTTPHeaderField: "x-requested-with")
    }

    private enum ZseV4 {
        private static let roundKeys: [UInt32] = [
            1170614578, 1024848638, 1413669199, 3951632832, 3528873006, 2921909214, 4151847688, 3997739139,
            1933479194, 3323781115, 3888513386, 460404854, 3747539722, 2403641034, 2615871395, 2119585428,
            2265697227, 2035090028, 2773447226, 4289380121, 4217216195, 2200601443, 3051914490, 1579901135,
            1321810770, 456816404, 2903323407, 4065664991, 330002838, 3506006750, 363569021, 2347096187
        ]
        private static let substitution: [UInt8] = [
            20, 223, 245, 7, 248, 2, 194, 209, 87, 6, 227, 253, 240, 128, 222, 91, 237, 9, 125, 157, 230,
            93, 252, 205, 90, 79, 144, 199, 159, 197, 186, 167, 39, 37, 156, 198, 38, 42, 43, 168, 217,
            153, 15, 103, 80, 189, 71, 191, 97, 84, 247, 95, 36, 69, 14, 35, 12, 171, 28, 114, 178, 148,
            86, 182, 32, 83, 158, 109, 22, 255, 94, 238, 151, 85, 77, 124, 254, 18, 4, 26, 123, 176, 232,
            193, 131, 172, 143, 142, 150, 30, 10, 146, 162, 62, 224, 218, 196, 229, 1, 192, 213, 27, 110,
            56, 231, 180, 138, 107, 242, 187, 54, 120, 19, 44, 117, 228, 215, 203, 53, 239, 251, 127, 81,
            11, 133, 96, 204, 132, 41, 115, 73, 55, 249, 147, 102, 48, 122, 145, 106, 118, 74, 190, 29, 16,
            174, 5, 177, 129, 63, 113, 99, 31, 161, 76, 246, 34, 211, 13, 60, 68, 207, 160, 65, 111, 82,
            165, 67, 169, 225, 57, 112, 244, 155, 51, 236, 200, 233, 58, 61, 47, 100, 137, 185, 64, 17, 70,
            234, 163, 219, 108, 170, 166, 59, 149, 52, 105, 24, 212, 78, 173, 45, 0, 116, 226, 119, 136,
            206, 135, 175, 195, 25, 92, 121, 208, 126, 139, 3, 75, 141, 21, 130, 98, 241, 40, 154, 66, 184,
            49, 181, 46, 243, 88, 101, 183, 8, 23, 72, 188, 104, 179, 210, 134, 250, 201, 164, 89, 216,
            202, 220, 50, 221, 152, 140, 33, 235, 214
        ]
        private static let alphabet = Array("6fpLRqJO8M/c3jnYxFkUVC4ZIG12SiH=5v0mXDazWBTsuw7QetbKdoPyAl+hN9rgE")
        private static let key = Array("059053f7d15e01d7".utf8)

        static func encrypt(_ input: String) -> String {
            var plain: [UInt8] = [210, 0]
            plain.append(contentsOf: input.utf8)
            let padding = 16 - (plain.count % 16)
            plain.append(contentsOf: repeatElement(UInt8(padding), count: padding))
            var first = Array(repeating: UInt8(0), count: 16)
            for index in 0..<16 { first[index] = plain[index] ^ key[index] ^ 42 }
            let firstCipher = block(first)
            var cipher = firstCipher
            var previous = firstCipher
            var offset = 16
            while offset < plain.count {
                let mixed = (0..<16).map { plain[offset + $0] ^ previous[$0] }
                previous = block(mixed)
                cipher.append(contentsOf: previous)
                offset += 16
            }
            return encode(cipher)
        }

        private static func block(_ input: [UInt8]) -> [UInt8] {
            var values = Array(repeating: UInt32(0), count: 36)
            for index in 0..<4 { values[index] = readUInt32(input, index * 4) }
            for index in 0..<32 {
                let mixed = values[index + 1] ^ values[index + 2] ^ values[index + 3] ^ roundKeys[index]
                values[index + 4] = values[index] ^ transform(mixed)
            }
            return [values[35], values[34], values[33], values[32]].flatMap(bytes)
        }

        private static func transform(_ value: UInt32) -> UInt32 {
            let b0 = substitution[Int((value >> 24) & 0xff)]
            let b1 = substitution[Int((value >> 16) & 0xff)]
            let b2 = substitution[Int((value >> 8) & 0xff)]
            let b3 = substitution[Int(value & 0xff)]
            let substituted = (UInt32(b0) << 24) | (UInt32(b1) << 16) | (UInt32(b2) << 8) | UInt32(b3)
            return substituted ^ rotateLeft(substituted, 2) ^ rotateLeft(substituted, 10) ^ rotateLeft(substituted, 18) ^ rotateLeft(substituted, 24)
        }

        private static func rotateLeft(_ value: UInt32, _ count: UInt32) -> UInt32 {
            (value << count) | (value >> (32 - count))
        }

        private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
            (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
        }

        private static func bytes(_ value: UInt32) -> [UInt8] {
            [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        }

        private static func encode(_ input: [UInt8]) -> String {
            var bytes = input
            let remainder = bytes.count % 3
            if remainder != 0 { bytes.append(contentsOf: repeatElement(UInt8(0), count: 3 - remainder)) }
            var output = ""
            var maskIndex = 0
            var pointer = bytes.count - 1
            while pointer >= 2 {
                var value = 0
                for shift in 0..<3 {
                    let byte = Int(bytes[pointer - shift])
                    let mask = (58 >> (8 * (maskIndex % 4))) & 0xff
                    maskIndex += 1
                    value |= ((byte ^ mask) & 0xff) << (8 * shift)
                }
                output.append(alphabet[value & 63])
                output.append(alphabet[(value >> 6) & 63])
                output.append(alphabet[(value >> 12) & 63])
                output.append(alphabet[(value >> 18) & 63])
                pointer -= 3
            }
            return output
        }
    }
}
