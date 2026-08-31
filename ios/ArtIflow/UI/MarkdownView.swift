import SwiftUI
import WebKit
import UIKit

/// 渲染 Markdown + LaTeX 的 SwiftUI 视图。
///
/// 渲染策略（避免助手回答空白）：
/// - 不含 LaTeX 的普通回答：用原生 `Text(AttributedString(markdown:))` 渲染，
///   自带高度、即时显示、无 WKWebView 时序问题，从根源上杜绝“塌成 0 高看不到”。
/// - 含 LaTeX（$ / $$ / \[ / \( ）的回答：走 WKWebView + KaTeX，渲染后通过
///   messageHandler 回传内容高度自适应；并加“未测到高度则降级原生文本”兜底，
///   即使 WebView 因任何原因失败，也保证内容可见。
struct MarkdownView: View {
    let markdown: String
    var textColor: Color = AppTheme.primaryText
    var fontSize: CGFloat = 16
    var textAlign: String = "left"

    @State private var measuredHeight: CGFloat = 1
    // WebView 一直未回高度时降级为原生文本，保证内容可见
    @State private var fallbackToNative = false

    private var needsWebView: Bool { containsLatexMarkdown(markdown) }

    var body: some View {
        Group {
            if needsWebView && !fallbackToNative {
                MarkdownWebView(
                    markdown: markdown,
                    textColor: textColor,
                    fontSize: fontSize,
                    textAlign: textAlign,
                    height: $measuredHeight,
                    onMeasured: { fallbackToNative = false }
                )
                .frame(height: max(measuredHeight, 1))
                .onAppear { scheduleFallback() }
            } else {
                NativeMarkdownText(markdown: markdown, textColor: textColor, fontSize: fontSize)
            }
        }
    }

    // WebView 路径下：若一段时间后仍未回高度，切到原生文本兜底
    private func scheduleFallback() {
        let current = markdown
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                if needsWebView && !fallbackToNative && measuredHeight < 8 && markdown == current {
                    fallbackToNative = true
                }
            }
        }
    }
}

/// 原生 Markdown 文本：用 Foundation 的 AttributedString(markdown:) 解析，
/// 支持 CommonMark 子集（标题/列表/加粗/斜体/代码/链接/引用），自带行高与选中。
private struct NativeMarkdownText: View {
    let markdown: String
    let textColor: Color
    let fontSize: CGFloat

    var body: some View {
        Text(parsed)
            .font(.system(size: fontSize))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var parsed: AttributedString {
        // 优先用完整块级解析（标题/列表/代码块/引用），失败再退回内联，最后回退原文
        if let full = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .full)) {
            return full
        }
        if let inline = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return inline
        }
        return AttributedString(markdown)
    }
}

/// 承载 WKWebView 的 UIViewRepresentable（仅用于含 LaTeX 的回答）
private struct MarkdownWebView: UIViewRepresentable {
    let markdown: String
    let textColor: Color
    let fontSize: CGFloat
    let textAlign: String
    @Binding var height: CGFloat
    var onMeasured: () -> Void

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
        // 触发首次模板加载（内含首帧渲染注入，加载完成后由 didFinish 接管后续更新）
        context.coordinator.render(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // 仅当模板加载完成后才注入最新内容，避免在页面尚未就绪时调用未定义的渲染函数
        if context.coordinator.isLoaded {
            webView.evaluateJavaScript(context.coordinator.buildInjection(), completionHandler: nil)
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: heightHandlerName)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static let heightHandlerName = "artiflowHeight"
}

private extension MarkdownWebView {
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        var isLoaded = false

        init(parent: MarkdownWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 模板与内联脚本就绪后再标记已加载，并立即渲染一次最新内容
            isLoaded = true
            webView.evaluateJavaScript(buildInjection(), completionHandler: nil)
        }

        // 接收模板回传的内容高度，更新 SwiftUI 的 frame，并标记已测到高度（取消降级）
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let h = body["height"] as? Double else { return }
            let value = max(CGFloat(h), 1)
            DispatchQueue.main.async { [weak self] in
                self?.parent.height = value
                self?.parent.onMeasured()
            }
        }

        /// 构造调用 window.artiflowRender(md, style) 的 JS 注入串。
        /// 用 JSON.stringify 风格的转义保证任意文本（含引号、反斜杠、$、换行）安全传入；
        /// 外层加 `if (window.artiflowRender)` 守卫，未就绪时静默跳过。
        private func buildInjection() -> String {
            let escaped = parent.markdown
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "</script>", with: "<\\/script>")
            return "if(window.artiflowRender){window.artiflowRender(\""
                + escaped
                + "\", { textColor: \"#" + parent.textColor.toHex()
                + "\", textAlign: \"" + parent.textAlign
                + "\", fontSize: " + String(Int(parent.fontSize)) + " });}"
        }

        func render(in webView: WKWebView) {
            // 首次加载模板并把首帧渲染注入追加到 HTML 末尾，加载完成自动执行
            if let templateUrl = Bundle.main.url(forResource: "MarkdownTemplate", withExtension: "html"),
               let template = try? String(contentsOf: templateUrl, encoding: .utf8) {
                let html = template + "<script>" + buildInjection() + "</script>"
                webView.loadHTMLString(html, baseURL: URL(string: "https://cdn.jsdelivr.net/"))
            } else {
                // 模板缺失：直接内联一段纯文本兜底
                let fallback = "<div style='font-family:-apple-system;padding:8px;color:#" + parent.textColor.toHex() + "'>" + parent.markdown.htmlEscaped + "</div>"
                webView.loadHTMLString(fallback, baseURL: nil)
                isLoaded = true
            }
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
