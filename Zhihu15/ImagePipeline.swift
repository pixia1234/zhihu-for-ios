import ImageIO
import UIKit

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
        directory = base.appendingPathComponent("zhihu15-images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL, completion: @escaping (UIImage?) -> Void) {
        guard let host = url.host?.lowercased(),
              url.scheme?.lowercased() == "https",
              host.hasSuffix("zhimg.com") || host.hasSuffix("zhihu.com") else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let key = url as NSURL
        if let image = memory.object(forKey: key) {
            DispatchQueue.main.async { completion(image) }
            return
        }

        let fileURL = diskURL(for: url)
        diskQueue.async { [weak self] in
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                self?.memory.setObject(image, forKey: key, cost: data.count)
                DispatchQueue.main.async { completion(image) }
                return
            }
            self?.session.dataTask(with: url) { [weak self] data, response, _ in
                guard let data = data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let image = UIImage(data: data) else {
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
}
