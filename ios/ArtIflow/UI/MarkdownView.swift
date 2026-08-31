import SwiftUI
import WebKit
import UIKit

/// 渲染 Markdown + LaTeX 的 SwiftUI 视图。内部用 WKWebView，并在渲染完成后
/// 通过 messageHandler 把内容高度回传给 SwiftUI，从而让外层 `.frame(height:)`
/// 自适应内容高度——否则 WKWebView 在 SwiftUI 中会塌成 0 高，导致助手回答看不见。
struct MarkdownView: View {
    let markdown: String
    var textColor: Color = AppTheme.primaryText
    var fontSize: CGFloat = 16
    var textAlign: String = "left"

    @State private var measuredHeight: CGFloat = 1

    var body: some View {
        MarkdownWebView(
            markdown: markdown,
            textColor: textColor,
            fontSize: fontSize,
            textAlign: textAlign,
            height: $measuredHeight
        )
        .frame(height: measuredHeight)
    }
}

/// 实际承载 WKWebView 的 UIViewRepresentable
private struct MarkdownWebView: UIViewRepresentable {
    let markdown: String
    let textColor: Color
    let fontSize: CGFloat
    let textAlign: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        // 注册高度回传的消息通道
        userContent.add(context.coordinator, name: Self.heightHandlerName)

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(in: webView)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 移除消息处理器，避免循环引用
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: heightHandlerName)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static let heightHandlerName = "artiflowHeight"
}

private extension MarkdownWebView {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        private var loadedTemplate = false

        init(parent: MarkdownWebView) { self.parent = parent }

        func render(in webView: WKWebView) {
            let injection = buildInjection()
            if loadedTemplate {
                // 已加载模板：直接调用渲染函数（内部会再次 post 高度）
                webView.evaluateJavaScript(injection, completionHandler: nil)
                return
            }
            if let templateUrl = Bundle.main.url(forResource: "MarkdownTemplate", withExtension: "html"),
               let template = try? String(contentsOf: templateUrl, encoding: .utf8) {
                let html = template + "<script>" + injection + "</script>"
                webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net/"))
                loadedTemplate = true
            } else {
                // 模板缺失时降级为纯文本
                let fallback = "<div style='font-family:-apple-system;padding:8px;color:#" + parent.textColor.toHex() + "'>" + parent.markdown.htmlEscaped + "</div>"
                webView.loadHTMLString(fallback, baseURL: nil)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(buildInjection(), completionHandler: nil)
        }

        // 接收模板回传的内容高度，更新 SwiftUI 的 frame
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let h = body["height"] as? Double else { return }
            DispatchQueue.main.async { [weak self] in
                self?.parent.height = max(CGFloat(h), 1)
            }
        }

        /// 构造调用 window.artiflowRender(md, style) 的 JS 注入串。
        /// 对 markdown 做 JS 字符串转义，并把 `</script>` 转义以避免提前闭合脚本。
        private func buildInjection() -> String {
            let payload = parent.markdown
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "</script>", with: "<\\/script>")
            return "window.artiflowRender(\"" + payload + "\", { textColor: \"#" + parent.textColor.toHex() + "\", textAlign: \"" + parent.textAlign + "\", fontSize: " + String(Int(parent.fontSize)) + " });"
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
