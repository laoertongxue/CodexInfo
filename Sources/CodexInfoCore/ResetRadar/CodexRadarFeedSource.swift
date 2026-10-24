import Foundation

/// The public RSS feed of the AI sentinel site (`codexradar.com/feed.xml`).
///
/// The feed publishes announcements about Codex usage resets. An item is only
/// reported as a confirmed reset when its own text says so; an announced but
/// unconfirmed window stays a `verifying` signal.
public struct CodexRadarFeedSource: ResetSource {
    public let id = "ai-sentinel-signals"
    public let displayName = "AI 哨兵信号"

    public init() {}

    public func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        var request = URLRequest(url: URL(string: "https://codexradar.com/feed.xml")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw HTTPError.status(response.statusCode) }

        let delegate = RSSDelegate()
        let parser = XMLParser(data: response.data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }

        return delegate.items.compactMap { item in
            guard let rawTitle = item["title"], !rawTitle.isEmpty else { return nil }
            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = item["description"] ?? ""
            let verified = Self.isConfirmed(title: title, description: description)
            // The feed publishes both announcements and the closing of a
            // window. A closed window is a completed reset, an open or
            // previewed one is still `verifying`. `verified` stays false
            // unless the item confirms the reset itself.
            let kind: ResetSignalKind = (verified || Self.isCompletion(title: title, description: description)) ? .reset : .verifying
            let scope = Self.scope(in: description)
            let url = Self.linkURL(itemLink: item["link"], description: description)
            return ResetSignal(
                id: "\(id):\(item["guid"] ?? title)",
                sourceId: id,
                sourceName: displayName,
                kind: kind,
                severity: nil,
                title: title,
                summary: description.trimmingCharacters(in: .whitespacesAndNewlines),
                publishedAt: DateParsing.rfc822(item["pubDate"]),
                url: url,
                verified: verified,
                scope: scope,
                confirmingSources: [displayName]
            )
        }
    }

    /// The item reports that the window closed and the reset landed.
    ///
    /// The feed uses the word 窗口 for an opening and for a closing, so the
    /// closing wording is checked first.
    static func isCompletion(title: String, description: String) -> Bool {
        let text = title + "\n" + description
        for phrase in ["窗口关闭", "已全部传播完成", "已完成", "已恢复", "恢复到 100%"] where text.contains(phrase) {
            return true
        }
        return false
    }

    /// The item counts as confirmed only when its own text says so.
    ///
    /// The phrases are matched exactly, so a negated wording such as
    /// `权益事件未确认` or `尚未确认完成` never reads as a confirmation.
    static func isConfirmed(title: String, description: String) -> Bool {
        title.contains("官方权益确认") || description.contains("权益事件已确认")
    }

    /// The scope of the announcement, read from its `适用范围：…` line.
    ///
    /// The line is missing on the short items, in which case the scope stays
    /// unknown instead of being guessed.
    static func scope(in description: String) -> String? {
        guard let line = description.split(separator: "\n").first(where: { $0.contains("适用范围") }) else {
            return nil
        }
        // Both the full width and the half width colon are accepted.
        let parts = line.split(whereSeparator: { $0 == "：" || $0 == ":" })
        guard parts.count >= 2 else { return nil }
        let value = String(parts[parts.count - 1]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    /// The link of the item, falling back to the first URL mentioned in the text.
    static func linkURL(itemLink: String?, description: String) -> URL? {
        if let itemLink, let url = URL(string: itemLink), url.scheme != nil { return url }
        for line in description.split(separator: "\n") {
            guard let range = line.range(of: "http") else { continue }
            // The line carries a label in front of the URL (`来源：https://…`),
            // so the URL starts at the first `http` and ends at the first
            // whitespace.
            let candidate = line[range.lowerBound...]
                .prefix { !$0.isWhitespace }
            if let url = URL(string: String(candidate)), url.scheme != nil { return url }
        }
        return nil
    }
}

/// A minimal RSS reader that collects the elements of every `<item>`.
///
/// The feed publishes plain text and CDATA, but the reader keeps a stack of the
/// open elements so that a nested element can never overwrite the text of its
/// parent.
private final class RSSDelegate: NSObject, XMLParserDelegate {
    var items: [[String: String]] = []

    private var current: [String: String] = [:]
    private var stack: [(name: String, text: String)] = []
    private var inItem = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        stack.append((name: elementName, text: ""))
        if elementName == "item" {
            inItem = true
            current = [:]
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard var top = stack.popLast() else { return }
        top.text += string
        stack.append(top)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let top = stack.popLast() else { return }
        if elementName == "item" {
            inItem = false
            items.append(current)
        } else if inItem, !top.text.isEmpty {
            current[elementName] = top.text
        }
    }
}
