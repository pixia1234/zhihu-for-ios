import AVFoundation
import UIKit
import WebKit

final class QRLoginViewController: UIViewController {
    private let scanner = QRScannerViewController()
    private var webController: QRAuthorizationWebViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "扫码登录"
        view.backgroundColor = .black
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        scanner.onCode = { [weak self] code in self?.handle(code: code) }
        scanner.onFailure = { [weak self] message in self?.showFailure(message) }
        addChild(scanner)
        scanner.view.frame = view.bounds
        scanner.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scanner.view)
        scanner.didMove(toParent: self)
    }

    @objc private func close() { dismiss(animated: true) }

    private func handle(code: String) {
        guard code.hasPrefix("https://www.zhihu.com/account/scan/login/"), let url = URL(string: code) else {
            showFailure("这不是知乎登录二维码")
            return
        }
        scanner.stopScanning()
        scanner.view.removeFromSuperview()
        scanner.removeFromParent()
        let controller = QRAuthorizationWebViewController(url: url)
        controller.onCompleted = { [weak self] in
            self?.dismiss(animated: true)
        }
        webController = controller
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    private func showFailure(_ message: String) {
        let alert = UIAlertController(title: "扫码失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重试", style: .default) { [weak self] _ in self?.scanner.startScanning() })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
}

final class QRAuthorizationWebViewController: UIViewController, WKNavigationDelegate {
    private let url: URL
    private let webView = WKWebView(frame: .zero)
    var onCompleted: (() -> Void)?
    private var didSave = false

    init(url: URL) { self.url = url; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didSave else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            let values = ZhihuCookieUtilities.values(from: cookies, for: URL(string: "https://www.zhihu.com/")!)
            guard values["d_c0"]?.isEmpty == false || values["z_c0"]?.isEmpty == false else { return }
            self.didSave = true
            var session = ZhihuAccountSession(cookies: values, userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15", profile: nil)
            try? ZhihuAccountStore.shared.save(session)
            ZhihuAPIClient.shared.fetchProfile { result in
                if case let .success(profile) = result {
                    session.profile = profile
                    try? ZhihuAccountStore.shared.save(session)
                }
                self.onCompleted?()
            }
        }
    }
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.pixia.zhihu15.client.qr-scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var delivered = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        prepareCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func startScanning() { delivered = false; prepareCamera() }

    func stopScanning() {
        delivered = true
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func prepareCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.configureSession() } else { self?.report("未获得相机权限") }
            }
        default: report("请在系统设置中允许相机权限")
        }
    }

    private func configureSession() {
        queue.async { [weak self] in
            guard let self = self, let device = AVCaptureDevice.default(for: .video) else { self?.report("当前设备没有可用相机"); return }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddInput(input), self.session.canAddOutput(output) else { self.report("无法启动二维码扫描"); return }
                self.session.addInput(input)
                self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                output.metadataObjectTypes = [.qr]
                DispatchQueue.main.async {
                    let layer = AVCaptureVideoPreviewLayer(session: self.session)
                    layer.videoGravity = .resizeAspectFill
                    layer.frame = self.view.bounds
                    self.view.layer.insertSublayer(layer, at: 0)
                    self.previewLayer = layer
                }
                self.session.startRunning()
            } catch { self.report(error.localizedDescription) }
        }
    }

    private func report(_ message: String) { DispatchQueue.main.async { [weak self] in self?.onFailure?(message) } }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered, let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let value = object.stringValue else { return }
        delivered = true
        stopScanning()
        onCode?(value)
    }
}
