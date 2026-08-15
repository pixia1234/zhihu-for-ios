import LocalAuthentication
import UIKit

final class AppLockCoordinator {
    static let shared = AppLockCoordinator()
    private let defaults = UserDefaults.standard
    private var lockController: AppLockViewController?

    var isEnabled: Bool { defaults.bool(forKey: "zhihu15.app-lock-enabled") }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: "zhihu15.app-lock-enabled")
        if !enabled { lockController?.dismiss(animated: false); lockController = nil }
    }

    func lock() {
        guard isEnabled else { return }
        lockController = nil
    }

    func presentIfNeeded(in window: UIWindow) {
        guard isEnabled, let root = window.rootViewController, lockController == nil else { return }
        let controller = AppLockViewController()
        controller.modalPresentationStyle = .fullScreen
        lockController = controller
        root.present(controller, animated: false)
    }

    func unlock(from controller: UIViewController) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            controller.showSimpleAlert(title: "无法解锁", message: error?.localizedDescription ?? "设备身份验证不可用")
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "解锁知乎") { [weak self, weak controller] success, error in
            DispatchQueue.main.async {
                guard let self = self, let controller = controller else { return }
                if success {
                    self.lockController = nil
                    controller.dismiss(animated: false)
                } else {
                    controller.showSimpleAlert(title: "解锁失败", message: error?.localizedDescription ?? "请重试")
                }
            }
        }
    }
}

final class AppLockViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let icon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        icon.tintColor = AppTheme.zhihuBlue
        icon.contentMode = .scaleAspectFit
        let title = UILabel()
        title.text = "知乎已锁定"
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let detail = UILabel()
        detail.text = "使用 Face ID、Touch ID 或设备密码解锁"
        detail.textColor = AppTheme.secondaryText
        detail.textAlignment = .center
        detail.numberOfLines = 0
        let button = UIButton(type: .system)
        button.setTitle("解锁", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = AppTheme.zhihuBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.addTarget(self, action: #selector(unlock), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [icon, title, detail, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 58), icon.heightAnchor.constraint(equalToConstant: 58),
            button.widthAnchor.constraint(equalToConstant: 150), button.heightAnchor.constraint(equalToConstant: 48),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        unlock()
    }

    @objc private func unlock() { AppLockCoordinator.shared.unlock(from: self) }
}

final class AppLockSettingsViewController: UIViewController {
    private let toggle = UISwitch()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "App 锁"
        view.backgroundColor = .systemGroupedBackground
        toggle.isOn = AppLockCoordinator.shared.isEnabled
        toggle.addTarget(self, action: #selector(valueChanged), for: .valueChanged)
        let titleLabel = UILabel()
        titleLabel.text = "使用 Face ID / Touch ID 解锁"
        titleLabel.font = .systemFont(ofSize: 16)
        let detail = UILabel()
        detail.text = "应用进入后台后再次打开时需要验证身份"
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = AppTheme.secondaryText
        let labels = UIStackView(arrangedSubviews: [titleLabel, detail])
        labels.axis = .vertical
        labels.spacing = 5
        let row = UIStackView(arrangedSubviews: [labels, toggle])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        row.backgroundColor = .secondarySystemGroupedBackground
        row.layer.cornerRadius = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
    }

    @objc private func valueChanged() {
        AppLockCoordinator.shared.setEnabled(toggle.isOn)
        if toggle.isOn { view.showSimpleAlert(title: "App 锁已开启", message: "下次从后台返回时会要求验证身份") }
    }
}

private extension UIViewController {
    func showSimpleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        present(alert, animated: true)
    }
}
