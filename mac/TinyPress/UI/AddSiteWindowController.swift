import AppKit

/// Modal sheet for registering a new site folder.
///
/// Programmatic AppKit only — no `.xib` / `.storyboard`. Wired up by
/// `StatusItemController` (Task 2.7) when the user picks "Add Site...".
@MainActor
final class AddSiteWindowController: NSWindowController, NSWindowDelegate {
    private let appState: AppState
    private let bookmarkManager: BookmarkManager
    private let nameField = NSTextField()
    private let folderField = NSTextField(labelWithString: "No folder chosen")
    private let chooseButton = NSButton(
        title: "Choose Folder…", target: nil, action: nil
    )
    private let addButton = NSButton(title: "Add", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var pendingFolder: (url: URL, bookmark: Data)?

    init(appState: AppState, bookmarkManager: BookmarkManager = BookmarkManager()) {
        self.appState = appState
        self.bookmarkManager = bookmarkManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add Site"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        installContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func installContent() {
        guard let contentView = window?.contentView else { return }

        let nameLabel = NSTextField(labelWithString: "Name")
        nameField.placeholderString = "My Blog"
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let folderLabel = NSTextField(labelWithString: "Folder")
        folderField.translatesAutoresizingMaskIntoConstraints = false
        folderField.lineBreakMode = .byTruncatingMiddle
        folderField.textColor = .secondaryLabelColor

        chooseButton.target = self
        chooseButton.action = #selector(chooseFolder)
        chooseButton.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addSite)
        addButton.keyEquivalent = "\r"
        addButton.isEnabled = false
        addButton.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [
            row(label: nameLabel, control: nameField),
            row(label: folderLabel, control: folderField, trailing: chooseButton),
            buttonRow(),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        nameField.delegate = self
    }

    private func row(label: NSTextField, control: NSView, trailing: NSView? = nil) -> NSView {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 60).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 8
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(control)
        if let trailing { stack.addArrangedSubview(trailing) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        if control is NSTextField {
            control.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        }
        stack.widthAnchor.constraint(equalToConstant: 348).isActive = true
        return stack
    }

    private func buttonRow() -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [spacer, cancelButton, addButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 348).isActive = true
        return stack
    }

    // MARK: Actions

    @objc private func chooseFolder() {
        Task { @MainActor in
            do {
                let result = try await bookmarkManager.pickFolder(
                    prompt: "Choose a tiny press site folder"
                )
                pendingFolder = result
                folderField.stringValue = result.url.path
                folderField.textColor = .labelColor
                if nameField.stringValue.isEmpty {
                    nameField.stringValue = result.url.lastPathComponent
                }
                refreshAddButton()
            } catch BookmarkError.userCancelled {
                // No-op: user dismissed the panel.
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func addSite() {
        guard let pending = pendingFolder else { return }
        let displayName = nameField.stringValue.isEmpty
            ? pending.url.lastPathComponent
            : nameField.stringValue
        Task { @MainActor in
            do {
                _ = try await appState.addSite(
                    folderBookmark: pending.bookmark,
                    name: displayName
                )
                close()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    @objc private func cancel() {
        close()
    }

    fileprivate func refreshAddButton() {
        addButton.isEnabled = pendingFolder != nil
    }
}

extension AddSiteWindowController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        refreshAddButton()
    }
}
