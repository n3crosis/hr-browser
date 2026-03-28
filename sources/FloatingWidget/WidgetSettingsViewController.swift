import UIKit

// Fully standalone — no dependency on SettingsToggle, Settings, or BlockerToggle.
// This means zero patches needed to existing app source files.
final class WidgetSettingsViewController: UITableViewController {

    private static let defaultsKey = "FloatingWidgetEnabled"
    private let widgetSwitch = UISwitch()

    init() {
        super.init(style: .grouped)
        title = "Widget"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        let isOn = UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true
        widgetSwitch.isOn = isOn
        widgetSwitch.onTintColor = .accent
        widgetSwitch.addTarget(self, action: #selector(switchChanged(_:)), for: .valueChanged)
    }

    // MARK: - Data source

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "WIDGET" }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Shows a draggable floating button on top of all content. Tap it to open this page."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "Show Floating Widget"
        cell.accessoryView = widgetSwitch
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - Actions

    @objc private func switchChanged(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: Self.defaultsKey)
        FloatingWidgetManager.shared.updateVisibility()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}
