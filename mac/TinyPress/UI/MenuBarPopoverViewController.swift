import AppKit
import Observation

/// Popover content shown when the user clicks the menu bar item.
///
/// Hosts the site table + bottom button row. Subscribes to `AppState`
/// changes via `withObservationTracking` while visible.
@MainActor
final class MenuBarPopoverViewController: NSViewController, NSTableViewDataSource,
    NSTableViewDelegate {

    let appState: AppState
    let openSettings: @MainActor () -> Void
    var onAddSite: (@MainActor () -> Void)?

    private let bookmarkManager = BookmarkManager()
    private let tailscaleStatusView = TailscaleStatusView()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton(title: "Add Site…", target: nil, action: nil)
    private let settingsButton = NSButton(title: "Settings…", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)

    private var resolvedPaths: [UUID: String] = [:]
    private var observationToken: UUID?

    init(appState: AppState, openSettings: @escaping @MainActor () -> Void) {
        self.appState = appState
        self.openSettings = openSettings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 360))
        root.translatesAutoresizingMaskIntoConstraints = false
        self.view = root
        installSubviews(in: root)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshResolvedPaths()
        renderTable()
        renderTailscale()
        // Probe tailscale up front so the strip already shows status when
        // the popover opens for the first time.
        Task { @MainActor in
            if appState.coordinator.tailscale.state == .unknown {
                await appState.coordinator.tailscale.detect()
                renderTailscale()
            }
        }
        observeAppState()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        observationToken = nil
    }

    private func installSubviews(in root: NSView) {
        let title = NSTextField(labelWithString: "tiny press")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.stringValue = "No sites yet. Click \u{201C}Add Site\u{2026}\u{201D} to get started."
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("site"))
        column.title = ""
        column.width = 320
        column.minWidth = 200
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 64
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.backgroundColor = .clear

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addSitePressed)
        settingsButton.target = self
        settingsButton.action = #selector(settingsPressed)
        quitButton.target = self
        quitButton.action = #selector(quitPressed)
        for button in [addButton, settingsButton, quitButton] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
        }

        let buttonRow = NSStackView(views: [addButton, settingsButton, NSView(), quitButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fill
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(title)
        root.addSubview(tailscaleStatusView)
        root.addSubview(scrollView)
        root.addSubview(emptyLabel)
        root.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),

            tailscaleStatusView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            tailscaleStatusView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            tailscaleStatusView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: tailscaleStatusView.bottomAnchor, constant: 8),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            buttonRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            buttonRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            buttonRow.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            buttonRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        tailscaleStatusView.isHidden = true
    }

    // MARK: Observation

    private func observeAppState() {
        let token = UUID()
        observationToken = token
        withObservationTracking { [weak self] in
            // Touch the properties we care about so the tracker registers.
            _ = self?.appState.sites
            _ = self?.appState.activePreview
            _ = self?.appState.coordinator.tailscale.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observationToken == token else { return }
                self.refreshResolvedPaths()
                self.renderTable()
                self.renderTailscale()
                // Re-arm tracking — withObservationTracking is one-shot.
                self.observeAppState()
            }
        }
    }

    private func renderTailscale() {
        let adapter = appState.coordinator.tailscale
        tailscaleStatusView.render(state: adapter.state) { [weak self] in
            Task { @MainActor in
                await adapter.detect()
                if let port = adapter.registeredPort {
                    await adapter.enable(localPort: port)
                }
                self?.renderTailscale()
            }
        }
    }

    private func refreshResolvedPaths() {
        var resolved: [UUID: String] = [:]
        for site in appState.sites {
            if let url = try? bookmarkManager.resolve(bookmark: site.folderBookmark).0 {
                resolved[site.id] = url.path
            }
        }
        self.resolvedPaths = resolved
    }

    private func renderTable() {
        emptyLabel.isHidden = !appState.sites.isEmpty
        tableView.reloadData()
    }

    // MARK: Actions

    @objc private func addSitePressed() {
        onAddSite?()
    }

    @objc private func settingsPressed() {
        openSettings()
    }

    @objc private func quitPressed() {
        NSApp.terminate(nil)
    }

    private func togglePreview(siteID: UUID) {
        let isActive = appState.activePreview == siteID
        Task {
            if isActive {
                await appState.stopPreview()
            } else {
                await appState.startPreview(id: siteID)
            }
        }
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        appState.sites.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        let site = appState.sites[row]
        let identifier = NSUserInterfaceItemIdentifier("siteRow")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: nil)
            as? SiteRowCellView)
            ?? {
                let view = SiteRowCellView()
                view.identifier = identifier
                return view
            }()
        cell.configure(
            site: site,
            resolvedPath: resolvedPaths[site.id],
            isActivePreview: appState.activePreview == site.id
        ) { [weak self] siteID in
            self?.togglePreview(siteID: siteID)
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 64 }
}
