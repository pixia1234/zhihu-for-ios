import UIKit

final class AccountListViewController: UITableViewController {
    private let store = ZhihuAccountStore.shared
    private var accounts: [ZhihuAccountSummary] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "账号管理"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AccountCell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "添加账号", style: .plain, target: self, action: #selector(addAccount))
        reloadAccounts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadAccounts()
    }

    private func reloadAccounts() {
        accounts = store.listAccounts()
        tableView.reloadData()
    }

    @objc private func addAccount() {
        let controller = UINavigationController(rootViewController: LoginViewController())
        if let login = controller.viewControllers.first as? LoginViewController {
            login.onLogin = { [weak self] in self?.reloadAccounts() }
        }
        present(controller, animated: true)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { accounts.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AccountCell", for: indexPath)
        let account = accounts[indexPath.row]
        cell.textLabel?.text = account.name
        cell.imageView?.image = UIImage(systemName: "person.crop.circle")
        cell.imageView?.tintColor = AppTheme.zhihuBlue
        cell.accessoryType = ZhihuAccountStore.shared.load()?.profile?.id == account.id ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let account = accounts[indexPath.row]
        do {
            try store.switchAccount(to: account.id)
            tableView.reloadData()
            navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "切换失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好的", style: .default))
            present(alert, animated: true)
        }
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let account = accounts[indexPath.row]
        do {
            try store.deleteAccount(account.id)
            reloadAccounts()
        } catch {
            let alert = UIAlertController(title: "删除失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好的", style: .default))
            present(alert, animated: true)
        }
    }
}
