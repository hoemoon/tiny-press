import AppKit
import TinyPressKit

/// Compact strip rendered above the site list in the menu bar popover.
/// Shows the current `TailscaleServeAdapter.State` with a copy-URL button
/// and a re-detect action; surfaces failures in red.
@MainActor
final class TailscaleStatusView: NSView {
    typealias RetryHandler = @MainActor () -> Void

    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let urlButton = NSButton(title: "", target: nil, action: nil)
    private let retryButton = NSButton(title: "Retry", target: nil, action: nil)
    private var copiedURL: URL?
    private var onRetry: RetryHandler?

    init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func render(state: TailscaleServeAdapter.State, onRetry: @escaping RetryHandler) {
        self.onRetry = onRetry

        switch state {
        case .unknown:
            isHidden = true
            return
        case .unavailable(let reason):
            isHidden = false
            icon.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Tailscale unavailable"
            )
            icon.contentTintColor = .systemOrange
            titleLabel.stringValue = "Tailscale: \(reason)"
            titleLabel.textColor = .secondaryLabelColor
            urlButton.isHidden = true
            retryButton.isHidden = false
            copiedURL = nil
        case .idle:
            isHidden = false
            icon.image = NSImage(
                systemSymbolName: "circle",
                accessibilityDescription: "Tailscale idle"
            )
            icon.contentTintColor = .secondaryLabelColor
            titleLabel.stringValue = "Tailscale ready — start a preview to share."
            titleLabel.textColor = .secondaryLabelColor
            urlButton.isHidden = true
            retryButton.isHidden = true
            copiedURL = nil
        case .starting:
            isHidden = false
            icon.image = NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath",
                accessibilityDescription: "Tailscale starting"
            )
            icon.contentTintColor = .secondaryLabelColor
            titleLabel.stringValue = "Registering with Tailscale Serve…"
            titleLabel.textColor = .secondaryLabelColor
            urlButton.isHidden = true
            retryButton.isHidden = true
            copiedURL = nil
        case .serving(let url):
            isHidden = false
            icon.image = NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: "Tailscale serving"
            )
            icon.contentTintColor = .systemGreen
            titleLabel.stringValue = "Shared on tailnet"
            titleLabel.textColor = .labelColor
            urlButton.title = url.absoluteString
            urlButton.isHidden = false
            retryButton.isHidden = true
            copiedURL = url
        case .failed(let message):
            isHidden = false
            icon.image = NSImage(
                systemSymbolName: "xmark.octagon.fill",
                accessibilityDescription: "Tailscale failed"
            )
            icon.contentTintColor = .systemRed
            titleLabel.stringValue = "Tailscale: \(message)"
            titleLabel.textColor = .systemRed
            urlButton.isHidden = true
            retryButton.isHidden = false
            copiedURL = nil
        }
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.4).cgColor
        layer?.cornerRadius = 6

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        urlButton.bezelStyle = .inline
        urlButton.controlSize = .small
        urlButton.target = self
        urlButton.action = #selector(copyURL)
        urlButton.toolTip = "Click to copy"
        urlButton.translatesAutoresizingMaskIntoConstraints = false
        urlButton.lineBreakMode = .byTruncatingMiddle

        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .small
        retryButton.target = self
        retryButton.action = #selector(retryPressed)
        retryButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(titleLabel)
        addSubview(urlButton)
        addSubview(retryButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: retryButton.leadingAnchor, constant: -8
            ),

            urlButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            urlButton.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            urlButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            urlButton.trailingAnchor.constraint(
                lessThanOrEqualTo: retryButton.leadingAnchor, constant: -8
            ),

            retryButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            retryButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc private func copyURL() {
        guard let url = copiedURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        let original = urlButton.title
        urlButton.title = "Copied ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            if self.copiedURL == url {
                self.urlButton.title = original
            }
        }
    }

    @objc private func retryPressed() {
        onRetry?()
    }
}
