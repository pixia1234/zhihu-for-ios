import UIKit

final class ProfileViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let accountStore = ZhihuAccountStore.shared
    private let profileNameLabel = UILabel()
    private let profileDetailLabel = UILabel()
    private let profileAvatar = AvatarView()
    private let rows = [
        ("个人主页", "person.crop.circle"),
        ("浏览记录", "clock.arrow.circlepath"),
        ("我的回答", "text.bubble"),
        ("账号管理", "person.2"),
        ("设置", "gearshape")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "账号"
        view.backgroundColor = .systemGroupedBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .systemGroupedBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.tableHeaderView = makeHeader()
        updateAccountAction()
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateAccountAction()
    }

    private func updateAccountAction() {
        if accountStore.load()?.isLoggedIn == true {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "退出", style: .plain, target: self, action: #selector(signOut))
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "登录", style: .plain, target: self, action: #selector(openLogin))
        }
        if let profile = accountStore.load()?.profile {
            profileNameLabel.text = profile.name
            profileDetailLabel.text = profile.headline?.isEmpty == false ? profile.headline : "记录思考，分享发现"
            profileAvatar.configure(name: profile.name, color: AppTheme.zhihuBlue)
            if let url = profile.avatarURL {
                ImagePipeline.shared.image(for: url) { [weak self] image in
                    self?.profileAvatar.layer.contents = image?.cgImage
                }
            }
        } else {
            profileNameLabel.text = "知乎用户"
            profileDetailLabel.text = "登录后同步你的收藏、历史与账号信息"
            profileAvatar.configure(name: "知", color: AppTheme.zhihuBlue)
            profileAvatar.layer.contents = nil
        }
    }

    @objc private func openLogin() {
        let controller = UINavigationController(rootViewController: LoginViewController())
        if let login = controller.viewControllers.first as? LoginViewController {
            login.onLogin = { [weak self] in self?.updateAccountAction() }
        }
        present(controller, animated: true)
    }

    @objc private func signOut() {
        let alert = UIAlertController(title: "退出登录", message: "清除本机保存的知乎登录信息？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "退出", style: .destructive) { [weak self] _ in
            try? self?.accountStore.clear()
            self?.updateAccountAction()
        })
        present(alert, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let header = tableView.tableHeaderView,
              header.frame.width != tableView.bounds.width,
              tableView.bounds.width > 0 else { return }
        header.frame.size.width = tableView.bounds.width
        tableView.tableHeaderView = header
    }

    private func makeHeader() -> UIView {
        let header = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 188))
        let card = UIView()
        card.backgroundColor = AppTheme.card
        card.layer.cornerRadius = 14
        profileAvatar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([profileAvatar.widthAnchor.constraint(equalToConstant: 64), profileAvatar.heightAnchor.constraint(equalToConstant: 64)])
        profileNameLabel.font = .systemFont(ofSize: 22, weight: .bold)
        profileDetailLabel.textColor = AppTheme.secondaryText
        profileDetailLabel.font = .systemFont(ofSize: 14)
        let info = UIStackView(arrangedSubviews: [profileNameLabel, profileDetailLabel])
        info.axis = .vertical
        info.spacing = 5
        let top = UIStackView(arrangedSubviews: [profileAvatar, info, UIView()])
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 14

        let stats = UIStackView()
        stats.axis = .horizontal
        stats.distribution = .fillEqually
        for (value, label) in [("12", "关注"), ("86", "获赞"), ("3", "收藏")] {
            let number = UILabel()
            number.text = value
            number.font = .systemFont(ofSize: 17, weight: .semibold)
            number.textAlignment = .center
            let caption = UILabel()
            caption.text = label
            caption.font = .systemFont(ofSize: 12)
            caption.textColor = AppTheme.secondaryText
            caption.textAlignment = .center
            let item = UIStackView(arrangedSubviews: [number, caption])
            item.axis = .vertical
            item.spacing = 3
            stats.addArrangedSubview(item)
        }

        let stack = UIStackView(arrangedSubviews: [top, stats])
        stack.axis = .vertical
        stack.spacing = 22
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        card.addSubview(stack)
        header.addSubview(card)
        card.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            card.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            card.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        return header
    }
}

extension ProfileViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.0
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.imageView?.image = UIImage(systemName: row.1)
        cell.imageView?.tintColor = AppTheme.zhihuBlue
        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

extension ProfileViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.row {
        case 0:
            if let token = accountStore.load()?.profile?.urlToken, let url = URL(string: "https://www.zhihu.com/people/\(token)") {
                navigationController?.pushViewController(WebContentViewController(url: url, title: "个人主页"), animated: true)
            } else { openLogin() }
        case 1:
            if accountStore.load()?.isLoggedIn == true {
                navigationController?.pushViewController(HistoryViewController(), animated: true)
            } else { openLogin() }
        case 2:
            if let url = URL(string: "https://www.zhihu.com/creator/feedback") {
                navigationController?.pushViewController(WebContentViewController(url: url, title: "我的回答"), animated: true)
            }
        case 3:
            navigationController?.pushViewController(AccountListViewController(), animated: true)
        default:
            navigationController?.pushViewController(AppLockSettingsViewController(), animated: true)
        }
    }
}
