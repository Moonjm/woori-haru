import SwiftUI
import UIKit
import WebKit

// MARK: - EmojiIconView

/// emoji 문자열이 "ico:" 접두사면 서버 SVG 아이콘을, 아니면 이모지 텍스트를 렌더링
struct EmojiIconView: View {
    let emoji: String
    let size: CGFloat

    var body: some View {
        if let iconName = emoji.iconName {
            SVGIconView(name: iconName, size: size)
        } else {
            Text(emoji)
                .font(.system(size: size))
        }
    }
}

// MARK: - String Extension

extension String {
    /// "ico:churros" → "churros", 일반 이모지 → nil
    var iconName: String? {
        hasPrefix("ico:") ? String(dropFirst(4)) : nil
    }

    /// 메뉴/라벨 표시용: "ico:churros" → "[churros]", 이모지 → 그대로
    var displayEmoji: String {
        if let name = iconName { return "[\(name)]" }
        return self
    }
}

// MARK: - SVG Icon View

private struct SVGIconView: View {
    let name: String
    let size: CGFloat

    @State private var svgString: String?

    var body: some View {
        Group {
            if let svgString {
                InlineSVGWebView(svgString: svgString, size: size)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .task(id: name) {
            svgString = await SVGDataCache.shared.svgString(for: name)
        }
    }
}

// MARK: - SVG Data Cache

/// SVG 문자열 다운로드 + 메모리 캐시
actor SVGDataCache {
    static let shared = SVGDataCache()

    private var cache: [String: String] = [:]

    func svgString(for name: String) async -> String? {
        if let cached = cache[name] { return cached }

        guard let url = URL(string: "https://daily.eunji.shop/icons/\(name).svg"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let string = String(data: data, encoding: .utf8) else { return nil }

        let processed = ensureViewBox(string)
        cache[name] = processed
        return processed
    }

    /// SVG에 viewBox가 없으면 width/height로 viewBox 추가
    private func ensureViewBox(_ svg: String) -> String {
        guard !svg.contains("viewBox") else { return svg }

        guard let w = extractAttr(svg, name: "width"),
              let h = extractAttr(svg, name: "height") else { return svg }

        var result = svg
        result = result.replacingOccurrences(of: "width=\"\(w)\"", with: "")
        result = result.replacingOccurrences(of: "height=\"\(h)\"", with: "")
        result = result.replacingOccurrences(
            of: "<svg ",
            with: "<svg viewBox=\"0 0 \(w) \(h)\" "
        )
        return result
    }

    private func extractAttr(_ svg: String, name: String) -> String? {
        let prefix = "\(name)=\""
        guard let startRange = svg.range(of: prefix) else { return nil }
        let afterPrefix = svg[startRange.upperBound...]
        guard let endQuote = afterPrefix.firstIndex(of: "\"") else { return nil }
        return String(afterPrefix[..<endQuote])
    }
}

// MARK: - Inline SVG WKWebView

/// WKWebView를 직접 뷰로 사용하여 SVG를 렌더링
private struct InlineSVGWebView: UIViewRepresentable {
    let svgString: String
    let size: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        loadSVG(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func loadSVG(in webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=\(Int(size)), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        * { margin: 0; padding: 0; }
        html, body {
            width: 100%;
            height: 100%;
            background: transparent;
            overflow: hidden;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        svg {
            width: 100%;
            height: 100%;
        }
        </style>
        </head>
        <body>\(svgString)</body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
