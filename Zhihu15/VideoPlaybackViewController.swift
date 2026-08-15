import AVKit
import Foundation
import UIKit

final class RemoteVideoRepository {
    static let shared = RemoteVideoRepository(client: .shared)
    private let client: ZhihuAPIClient

    init(client: ZhihuAPIClient) { self.client = client }

    func playbackURL(for item: FeedItem, completion: @escaping (Result<URL, Error>) -> Void) {
        guard let contentID = item.contentID, contentID > 0 else {
            completion(.failure(ZhihuSessionError.malformedPayload)); return
        }
        var components = URLComponents(string: "https://www.zhihu.com/api/v4/video/play_info")!
        components.queryItems = [URLQueryItem(name: "r", value: String(contentID))]
        let body: [String: Any] = [
            "content_id": String(contentID),
            "content_type_str": "zvideo",
            "video_id": String(contentID),
            "scene_code": "answer_detail_web",
            "is_only_video": true
        ]
        let data = try? JSONSerialization.data(withJSONObject: body, options: [])
        client.request(components.url!, method: "POST", body: data, headers: ["Content-Type": "application/json", "x-app-za": "OS=webplayer"], requiresLogin: false) { result in
            switch result {
            case let .failure(error): completion(.failure(error))
            case let .success(data):
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let videoPlay = root["video_play"] as? [String: Any],
                      let playlist = videoPlay["playlist"] as? [String: Any],
                      let mp4 = playlist["mp4"] as? [[String: Any]] else {
                    completion(.failure(ZhihuSessionError.malformedPayload)); return
                }
                let candidates = mp4.sorted { (a, b) in (a["bitrate"] as? Int ?? 0) > (b["bitrate"] as? Int ?? 0) }
                    .flatMap { $0["url"] as? [String] ?? [] }
                    .compactMap(URL.init(string:))
                    .filter { $0.scheme?.lowercased() == "https" }
                if let url = candidates.first { completion(.success(url)) }
                else { completion(.failure(ZhihuSessionError.malformedPayload)) }
            }
        }
    }
}

final class VideoPlaybackViewController: UIViewController {
    private let item: FeedItem
    private let activity = UIActivityIndicatorView(style: .large)
    private let messageLabel = UILabel()

    init(item: FeedItem) { self.item = item; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "视频"
        view.backgroundColor = .black
        activity.color = .white
        activity.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activity)
        view.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            activity.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activity.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            messageLabel.topAnchor.constraint(equalTo: activity.bottomAnchor, constant: 20)
        ])
        activity.startAnimating()
        RemoteVideoRepository.shared.playbackURL(for: item) { [weak self] result in
            guard let self = self else { return }
            self.activity.stopAnimating()
            switch result {
            case let .success(url):
                let player = AVPlayerViewController()
                player.player = AVPlayer(url: url)
                self.addChild(player)
                player.view.frame = self.view.bounds
                player.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                self.view.insertSubview(player.view, at: 0)
                player.didMove(toParent: self)
                player.player?.play()
            case let .failure(error): self.messageLabel.text = "视频暂时无法播放\n\(error.localizedDescription)"
            }
        }
    }
}
