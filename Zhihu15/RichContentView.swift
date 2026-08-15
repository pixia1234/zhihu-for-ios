import UIKit
import WebKit

/// A small, dependency-free rich content renderer for iOS 15.
///
/// Zhihu returns HTML for answers/articles while the editor and search entry
/// points also deal with Markdown-like text. Rendering both through one local
/// document keeps typography, links and images consistent without pulling a
/// large Markdown framework into the old-device build.
final class RichContentView: UIView, WKNavigationDelegate {
    private let webView: WKWebView
    private var heightConstraint: NSLayoutConstraint!

    var onOpenURL: ((URL) -> Void)?

    override init(frame: CGRect) {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)

        backgroundColor = .clear
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.customUserAgent = ZhihuAccountStore.shared.load()?.userAgent
            ?? "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
        webView.navigationDelegate = self
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInset = .zero
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        heightConstraint = webView.heightAnchor.constraint(equalToConstant: 1)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(markup: String) {
        let html = RichContentHTML.document(for: markup)
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.zhihu.com/"))
    }

    func clear() {
        heightConstraint.constant = 1
        webView.loadHTMLString(RichContentHTML.document(for: ""), baseURL: URL(string: "https://www.zhihu.com/"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateHeight()
        // Images arrive after the document finishes. Two inexpensive passes
        // avoid the common blank/one-line body on slower iOS 15 devices.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.updateHeight() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.updateHeight() }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        onOpenURL?(url)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard let url = navigationResponse.response.url else {
            decisionHandler(.allow)
            return
        }
        guard url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func updateHeight() {
        webView.evaluateJavaScript("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)") { [weak self] value, _ in
            guard let self = self,
                  let number = value as? NSNumber else { return }
            let height = max(28, CGFloat(truncating: number))
            guard abs(self.heightConstraint.constant - height) > 0.5 else { return }
            self.heightConstraint.constant = height
            self.invalidateIntrinsicContentSize()
            self.superview?.setNeedsLayout()
        }
    }
}

private enum RichContentHTML {
    static func document(for source: String) -> String {
        let content = looksLikeHTML(source) ? sanitizeHTML(source) : markdownHTML(source)
        return """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 0 1px; color: -apple-system-label; background: transparent; font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif; font-size: 17px; line-height: 1.68; overflow-wrap: anywhere; }
        p { margin: 0 0 0.9em; }
        h1, h2, h3 { line-height: 1.3; margin: 1.0em 0 0.45em; }
        h1 { font-size: 1.45em; } h2 { font-size: 1.25em; } h3 { font-size: 1.1em; }
        strong { font-weight: 700; } em { font-style: italic; }
        a { color: #1769d2; text-decoration: none; }
        img { display: block; max-width: 100%; height: auto; margin: 0.75em auto; border-radius: 8px; }
        blockquote { margin: 0.7em 0; padding: 0.1em 0.85em; border-left: 3px solid #1769d2; color: -apple-system-secondary-label; background: rgba(128,128,128,0.08); }
        pre, code { font-family: Menlo, monospace; font-size: 0.86em; }
        pre { overflow-x: auto; padding: 0.75em; border-radius: 8px; background: rgba(128,128,128,0.12); white-space: pre-wrap; }
        ul, ol { padding-left: 1.45em; margin-top: 0.2em; margin-bottom: 0.9em; }
        hr { border: 0; border-top: 1px solid rgba(128,128,128,0.3); margin: 1em 0; }
        </style></head><body>\(content)</body></html>
        """
    }

    private static func looksLikeHTML(_ source: String) -> Bool {
        source.range(of: #"<\s*(p|div|img|figure|h[1-6]|ul|ol|blockquote|br|a)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func sanitizeHTML(_ source: String) -> String {
        var html = source
        html = replace(html, pattern: #"(?is)<(script|iframe|object|embed|form|style)[^>]*>.*?</\1>"#, with: "")
        html = replace(html, pattern: #"(?is)<(script|iframe|object|embed|form|style)[^>]*/>"#, with: "")
        html = replace(html, pattern: #"(?i)\s+on[a-z]+\s*=\s*(\"[^\"]*\"|'[^']*')"#, with: "")
        html = replace(html, pattern: #"(?i)javascript:"#, with: "")
        html = replace(html, pattern: #"(?i)http://((?:pic|static|zhimg)[^\"'\s>]+)"#, with: "https://$1")
        // Zhihu occasionally sends a lazy-loading source in data-original or
        // data-src. When no normal src exists this makes the image visible.
        html = replace(html, pattern: #"(?i)<img([^>]*?)data-(?:original|src|actualsrc|lazy-src)\s*=\s*[\"']([^\"']+)[\"']([^>]*)>"#, with: "<img$1 src=\"$2\"$3>")
        return html
    }

    private static func markdownHTML(_ source: String) -> String {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        var lines: [String] = []
        var inList = false
        for rawLine in source.components(separatedBy: .newlines) {
            let line = inline(escape(rawLine.trimmingCharacters(in: .whitespaces)))
            if line.isEmpty {
                if inList { lines.append("</ul>"); inList = false }
                continue
            }
            if line.hasPrefix("### ") { lines.append("<h3>\(line.dropFirst(4))</h3>"); continue }
            if line.hasPrefix("## ") { lines.append("<h2>\(line.dropFirst(3))</h2>"); continue }
            if line.hasPrefix("# ") { lines.append("<h1>\(line.dropFirst(2))</h1>"); continue }
            if line.hasPrefix("> ") { lines.append("<blockquote>\(line.dropFirst(2))</blockquote>"); continue }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !inList { lines.append("<ul>"); inList = true }
                lines.append("<li>\(line.dropFirst(2))</li>")
                continue
            }
            if inList { lines.append("</ul>"); inList = false }
            lines.append("<p>\(line)</p>")
        }
        if inList { lines.append("</ul>") }
        return lines.joined()
    }

    private static func inline(_ value: String) -> String {
        var result = value
        result = replace(result, pattern: #"!\[([^\]]*)\]\((https?://[^)\s]+)\)"#, with: "<img alt=\"$1\" src=\"$2\">")
        result = replace(result, pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#, with: "<a href=\"$2\">$1</a>")
        result = replace(result, pattern: #"(?<![\"=])(https?://[^\s<]+)"#, with: "<a href=\"$1\">$1</a>")
        result = replace(result, pattern: #"`([^`]+)`"#, with: "<code>$1</code>")
        result = replace(result, pattern: #"\*\*([^*]+)\*\*|__([^_]+)__"#, with: "<strong>$1$2</strong>")
        result = replace(result, pattern: #"(?<!\*)\*([^*]+)\*(?!\*)|(?<!_)_([^_]+)_(?!_)"#, with: "<em>$1$2</em>")
        return result
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func replace(_ value: String, pattern: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else { return value }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: template)
    }
}
