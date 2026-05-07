import AppKit
import Foundation
import Observation
import TinyPressKit

/// "Sites" preferences tab — list of registered sites + tinypress.yml editor.
///
/// Edits write directly to the user's `tinypress.yml` so the source of truth
/// stays in their folder.
@MainActor
final class SitesPaneViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate {

    private let appState: AppState
    private let bookmarkManager = BookmarkManager()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let editorStack = NSStackView()
    private let titleField = NSTextField()
    private let descriptionField = NSTextField()
    private let authorField = NSTextField()
    private let baseURLField = NSTextField()
    private let languageField = NSTextField()
    private let permalinkPopup = NSPopUpButton()
    private let saveButton = NSButton(title: "Save", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove…", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private var observationToken: UUID?
    private var selectedSite: ManagedSite?

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 360))
        root.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.title = "Site"
        column.width = 160
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = false
        tableView.style = .plain
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .lineBorder

        for field in [titleField, descriptionField, authorField, baseURLField, languageField] {
            field.isEditable = true
            field.isBordered = true
            field.bezelStyle = .roundedBezel
        }
        permalinkPopup.addItems(withTitles: ["pretty", "file"])

        editorStack.orientation = .vertical
        editorStack.alignment = .leading
        editorStack.spacing = 8
        editorStack.translatesAutoresizingMaskIntoConstraints = false
        editorStack.addArrangedSubview(makeRow(label: "Title", control: titleField))
        editorStack.addArrangedSubview(makeRow(label: "Description", control: descriptionField))
        editorStack.addArrangedSubview(makeRow(label: "Author", control: authorField))
        editorStack.addArrangedSubview(makeRow(label: "Base URL", control: baseURLField))
        editorStack.addArrangedSubview(makeRow(label: "Language", control: languageField))
        editorStack.addArrangedSubview(makeRow(label: "Permalinks", control: permalinkPopup))

        saveButton.target = self
        saveButton.action = #selector(savePressed)
        removeButton.target = self
        removeButton.action = #selector(removePressed)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let actionRow = NSStackView(views: [saveButton, removeButton, NSView(), statusLabel])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        editorStack.addArrangedSubview(actionRow)

        root.addSubview(scrollView)
        root.addSubview(editorStack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            scrollView.widthAnchor.constraint(equalToConstant: 160),

            editorStack.leadingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 16),
            editorStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            editorStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
        ])
        self.view = root
        setEditorEnabled(false)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        observe()
        tableView.reloadData()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        observationToken = nil
    }

    private func observe() {
        let token = UUID()
        observationToken = token
        withObservationTracking { [weak self] in
            _ = self?.appState.sites
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationToken == token else { return }
                self.tableView.reloadData()
                self.observe()
            }
        }
    }

    private func makeRow(label: String, control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.alignment = .right
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: 90).isActive = true

        if let textField = control as? NSTextField {
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        } else {
            control.translatesAutoresizingMaskIntoConstraints = false
        }
        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func setEditorEnabled(_ enabled: Bool) {
        for field in [titleField, descriptionField, authorField, baseURLField, languageField] {
            field.isEnabled = enabled
        }
        permalinkPopup.isEnabled = enabled
        saveButton.isEnabled = enabled
        removeButton.isEnabled = enabled
    }

    private func loadConfig(for site: ManagedSite) {
        selectedSite = site
        guard
            let url = try? bookmarkManager.resolve(bookmark: site.folderBookmark).0
        else {
            statusLabel.stringValue = "Folder unavailable"
            statusLabel.textColor = .systemRed
            setEditorEnabled(false)
            return
        }
        try? bookmarkManager.beginAccessing(url)
        defer { bookmarkManager.stopAccessing(url) }

        let configURL = url.appendingPathComponent("tinypress.yml")
        if let config = try? SiteConfig.load(from: configURL) {
            titleField.stringValue = config.title
            descriptionField.stringValue = config.description ?? ""
            authorField.stringValue = config.author ?? ""
            baseURLField.stringValue = config.baseURL?.absoluteString ?? ""
            languageField.stringValue = config.language
            permalinkPopup.selectItem(withTitle: config.permalinkStyle.rawValue)
            statusLabel.stringValue = "Loaded from \(configURL.path)"
            statusLabel.textColor = .secondaryLabelColor
            setEditorEnabled(true)
        } else {
            statusLabel.stringValue = "tinypress.yml missing or invalid"
            statusLabel.textColor = .systemRed
            setEditorEnabled(false)
        }
    }

    @objc private func savePressed() {
        guard
            let site = selectedSite,
            let url = try? bookmarkManager.resolve(bookmark: site.folderBookmark).0
        else { return }
        try? bookmarkManager.beginAccessing(url)
        defer { bookmarkManager.stopAccessing(url) }

        let permalink: SiteConfig.PermalinkStyle =
            permalinkPopup.titleOfSelectedItem == "file" ? .file : .pretty
        let config = SiteConfig(
            title: titleField.stringValue,
            description: descriptionField.stringValue.nilIfEmpty,
            author: authorField.stringValue.nilIfEmpty,
            baseURL: URL(string: baseURLField.stringValue),
            theme: "default",
            language: languageField.stringValue.isEmpty ? "en" : languageField.stringValue,
            permalinkStyle: permalink
        )
        do {
            let configURL = url.appendingPathComponent("tinypress.yml")
            try config.save(to: configURL)
            statusLabel.stringValue = "Saved \(configURL.lastPathComponent)"
            statusLabel.textColor = .secondaryLabelColor
            if appState.activePreview == site.id {
                Task { await appState.coordinator.rebuild() }
            }
        } catch {
            statusLabel.stringValue = "Save failed: \(error)"
            statusLabel.textColor = .systemRed
        }
    }

    @objc private func removePressed() {
        guard let site = selectedSite else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \"\(site.name)\"?"
        alert.informativeText = "Files on disk are untouched."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await appState.removeSite(id: site.id)
            await MainActor.run { [weak self] in
                self?.selectedSite = nil
                self?.setEditorEnabled(false)
            }
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { appState.sites.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        let identifier = NSUserInterfaceItemIdentifier("siteName")
        let cell =
            (tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
            ?? {
                let cell = NSTableCellView()
                let label = NSTextField(labelWithString: "")
                label.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(label)
                cell.textField = label
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                ])
                cell.identifier = identifier
                return cell
            }()
        cell.textField?.stringValue = appState.sites[row].name
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard appState.sites.indices.contains(row) else {
            selectedSite = nil
            setEditorEnabled(false)
            return
        }
        loadConfig(for: appState.sites[row])
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { isEmpty ? nil : self }
}
