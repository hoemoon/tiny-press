import AppKit

/// One row in the site list. Programmatic — no `.xib`.
final class SiteRowCellView: NSTableCellView {
    typealias TogglePreviewAction = (UUID) -> Void

    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton(title: "Preview", target: nil, action: nil)
    private var siteID: UUID?
    private var onToggle: TogglePreviewAction?

    init() {
        super.init(frame: .zero)
        setupSubviews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func configure(
        site: ManagedSite,
        resolvedPath: String?,
        isActivePreview: Bool,
        onToggle: @escaping TogglePreviewAction
    ) {
        siteID = site.id
        self.onToggle = onToggle
        nameLabel.stringValue = site.name
        pathLabel.stringValue = resolvedPath ?? "(folder unavailable)"
        pathLabel.textColor = resolvedPath == nil ? .systemRed : .secondaryLabelColor
        statusLabel.stringValue = statusText(site: site, isActive: isActivePreview)
        actionButton.title = isActivePreview ? "Stop" : "Preview"
        actionButton.bezelColor = isActivePreview ? .systemRed : nil
    }

    @objc private func togglePressed() {
        guard let siteID, let onToggle else { return }
        onToggle(siteID)
    }

    private func setupSubviews() {
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor

        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .small
        actionButton.target = self
        actionButton.action = #selector(togglePressed)

        let textStack = NSStackView(views: [nameLabel, pathLabel, statusLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let row = NSStackView(views: [textStack, actionButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    private func statusText(site: ManagedSite, isActive: Bool) -> String {
        if isActive {
            if let port = site.previewPort {
                return "Live · http://127.0.0.1:\(port)"
            }
            return "Live"
        }
        if let date = site.lastBuildAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let phrase = formatter.localizedString(for: date, relativeTo: Date())
            return site.lastBuildSucceeded ? "Built \(phrase) ✓" : "Last build failed ✗"
        }
        return "Not built yet"
    }
}
