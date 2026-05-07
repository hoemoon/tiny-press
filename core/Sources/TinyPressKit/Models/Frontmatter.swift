import Foundation

/// Per-page YAML metadata extracted from the leading `---` block of a
/// markdown file.
public struct Frontmatter: Codable, Sendable, Equatable {
    /// Page title; usually rendered as `<h1>` and `<title>`.
    public var title: String?

    /// Publication date; surfaced to templates as ISO-8601.
    public var date: Date?

    /// Free-form tag list; defaults to empty when omitted.
    public var tags: [String]

    /// Custom slug overriding the file-name-derived slug.
    public var slug: String?

    /// Whether the page is a draft. Drafts are skipped unless
    /// `--include-drafts` is passed.
    public var draft: Bool

    /// Layout name override (e.g. `post`, `page`). When `nil` the builder
    /// falls back to the layout for the page kind.
    public var layout: String?

    /// User-defined fields preserved verbatim from the YAML block.
    public var extra: [String: FrontmatterValue]

    public init(
        title: String? = nil,
        date: Date? = nil,
        tags: [String] = [],
        slug: String? = nil,
        draft: Bool = false,
        layout: String? = nil,
        extra: [String: FrontmatterValue] = [:]
    ) {
        self.title = title
        self.date = date
        self.tags = tags
        self.slug = slug
        self.draft = draft
        self.layout = layout
        self.extra = extra
    }

    /// All-defaults frontmatter, used when a file has no metadata block.
    public static let empty = Frontmatter()

    private enum CodingKeys: String, CodingKey {
        case title, date, tags, slug, draft, layout, extra
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.date = try container.decodeIfPresent(Date.self, forKey: .date)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.slug = try container.decodeIfPresent(String.self, forKey: .slug)
        self.draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        self.layout = try container.decodeIfPresent(String.self, forKey: .layout)
        self.extra =
            try container.decodeIfPresent([String: FrontmatterValue].self, forKey: .extra) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(date, forKey: .date)
        if !tags.isEmpty { try container.encode(tags, forKey: .tags) }
        try container.encodeIfPresent(slug, forKey: .slug)
        if draft { try container.encode(draft, forKey: .draft) }
        try container.encodeIfPresent(layout, forKey: .layout)
        if !extra.isEmpty { try container.encode(extra, forKey: .extra) }
    }
}

/// Type-erased value usable inside `Frontmatter.extra`.
///
/// Kept self-contained — we deliberately avoid pulling in `AnyCodable` so the
/// kit's public surface stays free of third-party protocols.
public enum FrontmatterValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([FrontmatterValue])
    case dictionary([String: FrontmatterValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
            return
        }
        if let int = try? container.decode(Int.self) {
            self = .int(int)
            return
        }
        if let double = try? container.decode(Double.self) {
            self = .double(double)
            return
        }
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        if let array = try? container.decode([FrontmatterValue].self) {
            self = .array(array)
            return
        }
        if let dict = try? container.decode([String: FrontmatterValue].self) {
            self = .dictionary(dict)
            return
        }
        throw DecodingError.typeMismatch(
            FrontmatterValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported frontmatter value"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
