import AppKit

/// "Advanced" preferences tab — output-cache controls.
@MainActor
final class AdvancedPaneViewController: NSViewController {
    private let appState: AppState
    private let outputLabel = NSTextField(labelWithString: "")
    private let revealButton = NSButton(
        title: "Reveal in Finder", target: nil, action: nil
    )
    private let clearCacheButton = NSButton(
        title: "Clear Build Cache…", target: nil, action: nil
    )
    private let statusLabel = NSTextField(labelWithString: "")

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))

        let title = NSTextField(labelWithString: "Advanced")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let outputCaption = NSTextField(labelWithString: "Build output is stored at:")
        outputCaption.textColor = .secondaryLabelColor
        outputCaption.font = .systemFont(ofSize: 11)
        outputLabel.stringValue = Self.outputRootPath()
        outputLabel.font = .systemFont(ofSize: 12)
        outputLabel.lineBreakMode = .byTruncatingMiddle

        revealButton.target = self
        revealButton.action = #selector(revealPressed)
        clearCacheButton.target = self
        clearCacheButton.action = #selector(clearCachePressed)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let buttonRow = NSStackView(views: [revealButton, clearCacheButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [
            title, outputCaption, outputLabel, buttonRow, statusLabel,
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

    @objc private func revealPressed() {
        let url = URL(fileURLWithPath: Self.outputRootPath())
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func clearCachePressed() {
        let alert = NSAlert()
        alert.messageText = "Clear build cache?"
        alert.informativeText = "Generated previews for all sites will be removed. Source files are untouched."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let url = URL(fileURLWithPath: Self.outputRootPath())
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            statusLabel.stringValue = "Cleared \(url.path)"
            statusLabel.textColor = .secondaryLabelColor
        } catch {
            statusLabel.stringValue = "Clear failed: \(error)"
            statusLabel.textColor = .systemRed
        }
    }

    private static func outputRootPath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return appSupport.appendingPathComponent("TinyPress/builds", isDirectory: true).path
    }
}
