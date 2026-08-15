import ImageIO
import UIKit

enum ZhihuMediaURL {
    static func normalize(_ url: URL?) -> URL? {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443 else { return nil }
        if components.scheme?.lowercased() == "http" { components.scheme = "https" }
        components.fragment = nil
        guard components.scheme?.lowercased() == "https",
              host == "zhimg.com" || host.hasSuffix(".zhimg.com") || host == "zhihu.com" || host.hasSuffix(".zhihu.com") else { return nil }
        return components.url
    }

    static func from(_ value: Any?) -> URL? {
        guard let value = value as? String else { return nil }
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("//") { raw = "https:" + raw }
        return normalize(URL(string: raw))
    }
}

final class ImagePipeline {
    static let shared = ImagePipeline()

    private let memory = NSCache<NSURL, UIImage>()
    private let diskQueue = DispatchQueue(label: "com.example.zhihu15.image-cache", qos: .utility)
    private let session: URLSession
    private let directory: URL

    init() {
        memory.countLimit = 180
        memory.totalCostLimit = 48 * 1024 * 1024
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 64 * 1024 * 1024, diskPath: "zhihu-images")
        session = URLSession(configuration: configuration)
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // The old cache may contain AVIF/HTML responses produced by the
        // previous Accept header. Use a new namespace so iOS 15 never reuses
        // those undecodable/blank files after an app update.
        directory = base.appendingPathComponent("zhihu15-images-v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL, completion: @escaping (UIImage?) -> Void) {
        guard let normalizedURL = ZhihuMediaURL.normalize(url) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let key = normalizedURL as NSURL
        if let image = memory.object(forKey: key) {
            DispatchQueue.main.async { completion(image) }
            return
        }

        let fileURL = diskURL(for: normalizedURL)
        diskQueue.async { [weak self] in
            if let data = try? Data(contentsOf: fileURL), let image = Self.decode(data) {
                self?.memory.setObject(image, forKey: key, cost: data.count)
                DispatchQueue.main.async { completion(image) }
                return
            }
            var request = URLRequest(url: normalizedURL)
            request.cachePolicy = .useProtocolCachePolicy
            // Do not advertise AVIF first: iOS 15 devices cannot reliably
            // decode all AVIF responses returned by Zhihu's image CDN.
            request.setValue("image/jpeg,image/png,image/webp,image/gif,*/*;q=0.8", forHTTPHeaderField: "Accept")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue(ZhihuAccountStore.shared.load()?.userAgent ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
            request.setValue("https://www.zhihu.com/", forHTTPHeaderField: "Referer")
            self?.session.dataTask(with: request) { [weak self] data, response, _ in
                guard let data = data,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      Self.isImageResponse(http, data: data),
                      let image = Self.decode(data) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                self?.memory.setObject(image, forKey: key, cost: data.count)
                self?.diskQueue.async {
                    try? data.write(to: fileURL, options: [.atomic])
                }
                DispatchQueue.main.async { completion(image) }
            }.resume()
        }
    }

    func clear() {
        memory.removeAllObjects()
        diskQueue.async { [directory] in
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func diskURL(for url: URL) -> URL {
        let name = Data(url.absoluteString.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(name).appendingPathExtension("img")
    }

    private static func decode(_ data: Data) -> UIImage? {
        guard data.count > 64 else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private static func isImageResponse(_ response: HTTPURLResponse, data: Data) -> Bool {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() {
            if contentType.hasPrefix("image/") { return true }
            if contentType.contains("text/html") || contentType.contains("application/json") { return false }
        }
        // Some Zhihu CDN responses omit Content-Type. ImageIO remains the
        // source of truth in that case, but reject obvious HTML error pages.
        let prefix = String(data: data.prefix(32), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !(prefix?.hasPrefix("<html") == true || prefix?.hasPrefix("<!doctype") == true)
    }
}
