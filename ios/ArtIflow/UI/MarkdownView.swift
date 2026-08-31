import SwiftUI
import WebKit
import UIKit

/// Renders Markdown + LaTeX using a bundled HTML template that loads KaTeX from CDN.
/// Mirrors the Android Markwon + JLatexMath rendering path.
struct MarkdownView: UIViewRepresentable {
    let markdown: String
    var textColor: Color = AppTheme.primaryText
    var fontSize: CGFloat = 16
    var textAlign: String = "left"

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(in: webView)
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: MarkdownView
        var loadedTemplate = false

        init(parent: MarkdownView) {
            self.parent = parent
        }

        func render(in webView: WKWebView) {
            let injection = buildInjection()
            if loadedTemplate {
                webView.evaluateJavaScript(injection, completionHandler: nil)
                return
            }
            if let templateUrl = Bundle.main.url(forResource: "MarkdownTemplate", withExtension: "html"),
               let template = try? String(contentsOf: templateUrl, encoding: .utf8) {
                let html = template + "<script>\(injection)</script>"
                webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net/"))
                loadedTemplate = true
            } else {
                let fallback = "<div style='font-family:-apple-system;padding:8px;color:#\(parent.textColor.toHex())'>\(parent.markdown.htmlEscaped)</div>"
                webView.loadHTMLString(fallback, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(buildInjection(), completionHandler: nil)
        }

        private func buildInjection() -> String {
            let payload = parent.markdown
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "window.artiflowRender(\"\(payload)\", { textColor: \"#\(parent.textColor.toHex())\", textAlign: \"\(parent.textAlign)\", fontSize: \(Int(parent.fontSize)) });"
        }
    }
}

private extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

private extension String {
    var htmlEscaped: String {
        return self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
