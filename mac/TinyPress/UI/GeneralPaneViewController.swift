import AppKit

/// "General" preferences tab — global app settings.
@MainActor
final class GeneralPaneViewController: NSViewController {
    private let appState: AppState
    private let launchAtLoginToggle = NSButton(
        checkboxWithTitle: "Launch at login", target: nil, action: nil
    )
    private let notifyOnFailureToggle = NSButton(
        checkboxWithTitle: "Notify when a build fails", target: nil, action: nil
    )

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))

        let title = NSTextField(labelWithString: "General")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let stack = NSStackView(views: [
            title,
            launchAtLoginToggle,
            notifyOnFailureToggle,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
        ])
        self.view = root
    }
}
