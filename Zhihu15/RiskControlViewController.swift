import UIKit
import WebKit

final class RiskControlViewController: UIViewController, WKNavigationDelegate {
    private let url: URL
    private let cookies: [String: String]
    private let webView = WKWebView(frame: .zero)
    private let statusLabel = UILabel()
    var onCompleted: (() -> Void)?

    init(url: URL, cookies: [String: String]) {
        self.url = url
        self.cookies = cookies
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "安全验证"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成验证", style: .done, target: self, action: #selector(complete))
        statusLabel.text = "正在加载安全验证页面…"
        statusLabel.textColor = AppTheme.secondaryText
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            statusLabel.heightAnchor.constraint(equalToConstant: 22),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 6),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let store = webView.configuration.websiteDataStore.httpCookieStore
        ZhihuCookieUtilities.install(ZhihuCookieUtilities.makeCookies(from: cookies, for: url), in: store) { [weak self] in
            guard let self = self else { return }
            self.webView.load(URLRequest(url: self.url))
        }
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func complete() {
        statusLabel.text = "正在提交验证信息…"
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            let values = ZhihuCookieUtilities.values(from: cookies, for: URL(string: "https://www.zhihu.com/")!)
            guard var session = ZhihuAccountStore.shared.load() else { self.statusLabel.text = "当前没有可更新的账号"; return }
            session.cookies.merge(values) { _, incoming in incoming }
            try? ZhihuAccountStore.shared.save(session)
            ZhihuAPIClient.shared.fetchProfile { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.dismiss(animated: true) { self.onCompleted?() }
                case let .failure(error): self.statusLabel.text = error.localizedDescription
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { statusLabel.text = "正在加载安全验证页面…" }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { statusLabel.text = "完成验证后点击右上角按钮" }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { statusLabel.text = error.localizedDescription }
}
