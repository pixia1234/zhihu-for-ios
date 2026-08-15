import UIKit
import WebKit

final class LoginViewController: UIViewController {
    private let webView: WKWebView
    private let accountStore = ZhihuAccountStore.shared
    private var isFinishing = false
    var onLogin: (() -> Void)?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "登录知乎"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "扫码登录", style: .plain, target: self, action: #selector(openQRLogin))
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        webView.load(URLRequest(url: URL(string: "https://www.zhihu.com/signin?next=%2F")!))
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func openQRLogin() {
        let controller = UINavigationController(rootViewController: QRLoginViewController())
        present(controller, animated: true)
    }

    private func inspectCookies() {
        guard !isFinishing else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            var values: [String: String] = [:]
            for cookie in cookies where cookie.domain.lowercased().contains("zhihu.com") {
                values[cookie.name] = cookie.value
            }
            guard values["d_c0"]?.isEmpty == false || values["z_c0"]?.isEmpty == false else { return }
            self.isFinishing = true
            var session = ZhihuAccountSession(cookies: values, userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15", profile: nil)
            do {
                try self.accountStore.save(session)
                ZhihuAPIClient.shared.fetchProfile { [weak self] result in
                    guard let self = self else { return }
                    if case let .success(profile) = result {
                        session.profile = profile
                        try? self.accountStore.save(session)
                        self.dismiss(animated: true) { self.onLogin?() }
                    } else if case .failure = result {
                        self.isFinishing = false
                        let risk = UINavigationController(rootViewController: RiskControlViewController(url: URL(string: "https://www.zhihu.com/account/risk_control/")!, cookies: values))
                        if let riskController = risk.viewControllers.first as? RiskControlViewController {
                            riskController.onCompleted = { [weak self] in self?.dismiss(animated: true) { self?.onLogin?() } }
                        }
                        self.present(risk, animated: true)
                    }
                }
            } catch {
                self.isFinishing = false
                self.showError(error.localizedDescription)
            }
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "登录失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

extension LoginViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        inspectCookies()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showError(error.localizedDescription) }
    }
}
