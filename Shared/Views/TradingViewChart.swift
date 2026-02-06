import SwiftUI
import WebKit

/// TradingView chart embedded in a WebView
struct TradingViewChart: View {
    let symbol: String
    var interval: String = "D"
    var theme: String = "dark"

    var body: some View {
        TradingViewWebView(symbol: symbol, interval: interval, theme: theme)
    }
}

#if os(macOS)
struct TradingViewWebView: NSViewRepresentable {
    let symbol: String
    let interval: String
    let theme: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        loadChart(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadChart(in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadChart(in webView: WKWebView) {
        let html = generateChartHTML()
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.tradingview.com"))
    }

    private func generateChartHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: \(theme == "dark" ? "#1e1e1e" : "#ffffff"); }
                .tradingview-widget-container { width: 100%; height: 100%; }
            </style>
        </head>
        <body>
            <div class="tradingview-widget-container">
                <div id="tradingview_chart" style="width: 100%; height: 100%;"></div>
            </div>
            <script type="text/javascript" src="https://s3.tradingview.com/tv.js"></script>
            <script type="text/javascript">
                new TradingView.widget({
                    "autosize": true,
                    "symbol": "\(symbol)",
                    "interval": "\(interval)",
                    "timezone": "Etc/UTC",
                    "theme": "\(theme)",
                    "style": "1",
                    "locale": "en",
                    "toolbar_bg": "\(theme == "dark" ? "#1e1e1e" : "#f1f3f6")",
                    "enable_publishing": false,
                    "hide_top_toolbar": false,
                    "hide_legend": false,
                    "save_image": false,
                    "container_id": "tradingview_chart",
                    "hide_volume": false
                });
            </script>
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("TradingView load error: \(error)")
        }
    }
}
#else
struct TradingViewWebView: UIViewRepresentable {
    let symbol: String
    let interval: String
    let theme: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        loadChart(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadChart(in: webView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func loadChart(in webView: WKWebView) {
        let html = generateChartHTML()
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.tradingview.com"))
    }

    private func generateChartHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body { width: 100%; height: 100%; overflow: hidden; background: \(theme == "dark" ? "#1e1e1e" : "#ffffff"); }
                .tradingview-widget-container { width: 100%; height: 100%; }
            </style>
        </head>
        <body>
            <div class="tradingview-widget-container">
                <div id="tradingview_chart" style="width: 100%; height: 100%;"></div>
            </div>
            <script type="text/javascript" src="https://s3.tradingview.com/tv.js"></script>
            <script type="text/javascript">
                new TradingView.widget({
                    "autosize": true,
                    "symbol": "\(symbol)",
                    "interval": "\(interval)",
                    "timezone": "Etc/UTC",
                    "theme": "\(theme)",
                    "style": "1",
                    "locale": "en",
                    "toolbar_bg": "\(theme == "dark" ? "#1e1e1e" : "#f1f3f6")",
                    "enable_publishing": false,
                    "hide_top_toolbar": false,
                    "hide_legend": false,
                    "save_image": false,
                    "container_id": "tradingview_chart",
                    "hide_volume": false
                });
            </script>
        </body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("TradingView load error: \(error)")
        }
    }
}
#endif

// MARK: - Token Symbol Mapping

extension String {
    /// Maps token symbols to TradingView symbols
    var tradingViewSymbol: String {
        switch self.uppercased() {
        case "ETH", "WETH":
            return "COINBASE:ETHUSD"
        case "BTC", "WBTC":
            return "COINBASE:BTCUSD"
        case "USDC":
            return "COINBASE:USDCUSD"
        case "USDT":
            return "BINANCE:USDTUSD"
        case "DAI":
            return "COINBASE:DAIUSD"
        case "UNI":
            return "COINBASE:UNIUSD"
        case "LINK":
            return "COINBASE:LINKUSD"
        case "AAVE":
            return "COINBASE:AAVEUSD"
        case "CRV":
            return "COINBASE:CRVUSD"
        case "MKR":
            return "COINBASE:MKRUSD"
        case "COMP":
            return "COINBASE:COMPUSD"
        case "SNX":
            return "COINBASE:SNXUSD"
        case "SUSHI":
            return "COINBASE:SUSHIUSD"
        case "YFI":
            return "COINBASE:YFIUSD"
        case "1INCH":
            return "COINBASE:1INCHUSD"
        case "ENS":
            return "COINBASE:ENSUSD"
        case "LDO":
            return "COINBASE:LDOUSD"
        case "RPL":
            return "COINBASE:RPLUSD"
        case "ARB":
            return "COINBASE:ARBUSD"
        case "OP":
            return "COINBASE:OPUSD"
        case "MATIC", "POL":
            return "COINBASE:MATICUSD"
        case "SHIB":
            return "COINBASE:SHIBUSD"
        case "PEPE":
            return "COINBASE:PEPEUSD"
        default:
            // Try Coinbase first, fallback to Binance
            return "COINBASE:\(self.uppercased())USD"
        }
    }
}

#Preview {
    TradingViewChart(symbol: "COINBASE:ETHUSD")
        .frame(width: 600, height: 400)
}
