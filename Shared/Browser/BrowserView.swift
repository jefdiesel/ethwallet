import SwiftUI
import WebKit
import Combine

// MARK: - Browser Tab Model

@MainActor
class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String = "New Tab"
    @Published var url: URL?
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isSecure = false

    let webView: WKWebView
    var coordinator: TabCoordinator?

    init(webView: WKWebView) {
        self.webView = webView
    }
}

// MARK: - Browser ViewModel

@MainActor
class BrowserViewModel: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var activeTabId: UUID?
    @Published var pendingSignRequest: Web3Request?
    @Published var pendingSignTab: BrowserTab?

    var connectedAddress: String?
    private var tabCancellables: [UUID: Set<AnyCancellable>] = [:]

    var activeTab: BrowserTab? {
        tabs.first { $0.id == activeTabId }
    }

    // Create a new tab, optionally with a URL
    func createTab(url: URL? = nil, switchTo: Bool = true) -> BrowserTab {
        let configuration = Self.makeWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true

        let tab = BrowserTab(webView: webView)
        let coordinator = TabCoordinator(tab: tab, browserModel: self)
        tab.coordinator = coordinator

        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        configuration.userContentController.add(coordinator, name: "ethWallet")

        tabs.append(tab)

        // Observe tab changes to republish
        var cancellables = Set<AnyCancellable>()
        tab.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        tabCancellables[tab.id] = cancellables

        if switchTo {
            activeTabId = tab.id
        }

        if let url = url {
            webView.load(URLRequest(url: url))
        } else {
            webView.load(URLRequest(url: URL(string: "https://chainhost.online")!))
        }

        // Set connected address if available
        if let address = connectedAddress {
            let js = "window._ethWalletEvent && window._ethWalletEvent('accountsChanged', ['\(address.lowercased())']);"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        return tab
    }

    func closeTab(_ tabId: UUID) {
        guard tabs.count > 1 else { return } // Keep at least one tab

        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            let tab = tabs[index]
            tab.webView.stopLoading()
            tab.coordinator = nil
            tabCancellables.removeValue(forKey: tabId)
            tabs.remove(at: index)

            // If we closed the active tab, switch to nearest
            if activeTabId == tabId {
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
            }
        }
    }

    func navigate(to urlString: String) {
        guard let tab = activeTab else { return }
        var urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }

        if !urlString.contains("://") {
            if urlString.contains(".") {
                urlString = "https://" + urlString
            } else {
                urlString = "https://duckduckgo.com/?q=" + (urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
            }
        }

        guard let url = URL(string: urlString) else { return }
        tab.webView.load(URLRequest(url: url))
    }

    func goBack() { activeTab?.webView.goBack() }
    func goForward() { activeTab?.webView.goForward() }

    func reload() {
        guard let tab = activeTab else { return }
        if tab.isLoading {
            tab.webView.stopLoading()
        } else {
            tab.webView.reload()
        }
    }

    func goHome() { navigate(to: "https://chainhost.online") }

    func setAccount(_ address: String) {
        connectedAddress = address
        for tab in tabs {
            let js = "window._ethWalletEvent && window._ethWalletEvent('accountsChanged', ['\(address.lowercased())']);"
            tab.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func respondToRequest(id: Double, result: Any?, error: String?, tab: BrowserTab) {
        let js: String
        if let error = error {
            let escaped = error.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            js = "window._ethWalletResponse && window._ethWalletResponse(\(id), null, '\(escaped)');"
        } else if let result = result {
            let jsonValue = serializeToJS(result)
            js = "window._ethWalletResponse && window._ethWalletResponse(\(id), \(jsonValue), null);"
        } else {
            js = "window._ethWalletResponse && window._ethWalletResponse(\(id), null, null);"
        }

        print("[Browser] respondToRequest id=\(id) js=\(js.prefix(120))...")
        tab.webView.evaluateJavaScript(js) { returnValue, jsError in
            if let jsError = jsError {
                print("[Browser] evaluateJavaScript ERROR: \(jsError)")
            } else {
                print("[Browser] evaluateJavaScript OK, returned: \(String(describing: returnValue))")
            }
        }
    }

    private func serializeToJS(_ value: Any) -> String {
        if value is NSNull {
            return "null"
        }
        if let stringValue = value as? String {
            let escaped = stringValue.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }
        if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        }
        if let numValue = value as? NSNumber {
            return "\(numValue)"
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        return "null"
    }

    // MARK: - WebView Configuration Factory

    static func makeWebViewConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()

        // Inject Web3 provider at document start
        if let scriptURL = Bundle.main.url(forResource: "Web3Provider", withExtension: "js"),
           let scriptContent = try? String(contentsOf: scriptURL) {
            let script = WKUserScript(source: scriptContent, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(script)
        } else {
            let script = WKUserScript(source: Web3ProviderScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            configuration.userContentController.addUserScript(script)
        }

        // Inject pixel art rendering (nearest-neighbor for small/pixel-art images)
        let pixelArtScript = WKUserScript(
            source: """
            (function() {
                var processed = new WeakSet();
                function isPixelArt(img) {
                    if (!img.naturalWidth || !img.naturalHeight) return false;
                    // Small source images displayed larger = pixel art
                    if (img.naturalWidth <= 256 && img.naturalHeight <= 256) return true;
                    // Data URIs with small images (ethscriptions, on-chain SVGs)
                    if (img.src && (img.src.startsWith('data:image/png') || img.src.startsWith('data:image/gif') || img.src.startsWith('data:image/bmp'))) {
                        if (img.naturalWidth <= 512 && img.naturalHeight <= 512) return true;
                    }
                    return false;
                }
                function applyToImg(img) {
                    if (processed.has(img)) return;
                    function check() {
                        if (isPixelArt(img)) {
                            img.style.imageRendering = 'pixelated';
                            processed.add(img);
                        }
                    }
                    if (img.complete && img.naturalWidth > 0) check();
                    else img.addEventListener('load', check, { once: true });
                }
                function applyToSVG(svg) {
                    // SVGs containing embedded raster images (wrapped ethscription tokenURIs)
                    svg.querySelectorAll('image').forEach(function(img) {
                        img.setAttribute('image-rendering', 'pixelated');
                        img.style.imageRendering = 'pixelated';
                    });
                }
                function scan() {
                    document.querySelectorAll('img').forEach(applyToImg);
                    document.querySelectorAll('svg').forEach(applyToSVG);
                    // Canvas elements showing pixel art
                    document.querySelectorAll('canvas').forEach(function(c) {
                        if (c.width <= 256 && c.height <= 256) {
                            c.style.imageRendering = 'pixelated';
                        }
                    });
                }
                // Inject a global CSS rule as fallback for common NFT image patterns
                var style = document.createElement('style');
                style.textContent = 'img[src*="data:image/png"], img[src*="data:image/gif"], img[src*="data:image/bmp"], img[src*="data:image/svg"] { image-rendering: pixelated; } svg image { image-rendering: pixelated; }';
                (document.head || document.documentElement).appendChild(style);

                var observer = new MutationObserver(function(mutations) {
                    for (var m of mutations) {
                        if (m.type === 'childList') { scan(); }
                        else if (m.type === 'attributes' && m.target.tagName === 'IMG') { applyToImg(m.target); }
                    }
                });
                function startObserver() {
                    observer.observe(document.body || document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'srcset'] });
                }
                if (document.body) startObserver();
                else document.addEventListener('DOMContentLoaded', startObserver);
                document.addEventListener('DOMContentLoaded', scan);
                if (document.readyState !== 'loading') scan();
                // Re-scan periodically for lazy-loaded content
                setInterval(scan, 3000);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(pixelArtScript)

        // Privacy & settings
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Content blocking
        let blockRules = """
        [
            { "trigger": { "url-filter": ".*", "resource-type": ["script"], "if-domain": ["*google-analytics.com", "*googletagmanager.com", "*facebook.net", "*doubleclick.net"] }, "action": { "type": "block" } },
            { "trigger": { "url-filter": ".*", "resource-type": ["script"], "if-domain": ["*hotjar.com", "*mixpanel.com", "*segment.com", "*amplitude.com"] }, "action": { "type": "block" } }
        ]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "TrackerBlocker",
            encodedContentRuleList: blockRules
        ) { ruleList, _ in
            if let ruleList = ruleList {
                configuration.userContentController.add(ruleList)
            }
        }

        return configuration
    }
}

// MARK: - Tab Coordinator

class TabCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var tab: BrowserTab?
    weak var browserModel: BrowserViewModel?
    private let networkManager = NetworkManager.shared

    init(tab: BrowserTab, browserModel: BrowserViewModel) {
        self.tab = tab
        self.browserModel = browserModel
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "ethWallet",
              let body = message.body as? [String: Any],
              let id = body["id"] as? Double,
              let method = body["method"] as? String else { return }

        let params = body["params"] as? [Any] ?? []

        Task { @MainActor in
            await handleWeb3Request(id: id, method: method, params: params)
        }
    }

    @MainActor
    private func handleWeb3Request(id: Double, method: String, params: [Any]) async {
        guard let tab = tab, let browserModel = browserModel else { return }

        switch method {
        case "eth_requestAccounts", "eth_accounts":
            if let address = browserModel.connectedAddress {
                browserModel.respondToRequest(id: id, result: [address.lowercased()], error: nil, tab: tab)
            } else {
                browserModel.respondToRequest(id: id, result: [] as [String], error: "No account", tab: tab)
            }

        case "eth_chainId":
            let chainId = "0x" + String(networkManager.selectedNetwork.id, radix: 16)
            browserModel.respondToRequest(id: id, result: chainId, error: nil, tab: tab)

        case "net_version":
            browserModel.respondToRequest(id: id, result: String(networkManager.selectedNetwork.id), error: nil, tab: tab)

        case "personal_sign", "eth_sign", "eth_sendTransaction", "eth_signTypedData", "eth_signTypedData_v4":
            print("[Browser] Sign request: \(method), showing sheet")
            let request = Web3Request(id: id, method: method, params: params)
            browserModel.pendingSignRequest = request
            browserModel.pendingSignTab = tab

        case "wallet_switchEthereumChain":
            if let chainParam = params.first as? [String: Any],
               let chainIdHex = chainParam["chainId"] as? String {
                let chainId = Int(chainIdHex.dropFirst(2), radix: 16) ?? 1
                if let network = Network.forChainId(chainId) {
                    networkManager.selectNetwork(network)
                    browserModel.respondToRequest(id: id, result: NSNull(), error: nil, tab: tab)
                    let js = "window._ethWalletEvent && window._ethWalletEvent('chainChanged', '\(chainIdHex)');"
                    tab.webView.evaluateJavaScript(js, completionHandler: nil)
                } else {
                    browserModel.respondToRequest(id: id, result: nil, error: "Chain not supported", tab: tab)
                }
            }

        default:
            await forwardRPCCall(id: id, method: method, params: params, tab: tab)
        }
    }

    @MainActor
    private func forwardRPCCall(id: Double, method: String, params: [Any], tab: BrowserTab) async {
        guard let browserModel = browserModel else { return }
        let web3Service = Web3Service(network: networkManager.selectedNetwork)
        do {
            let result = try await web3Service.rawRPCCall(method: method, params: params)
            browserModel.respondToRequest(id: id, result: result, error: nil, tab: tab)
        } catch {
            browserModel.respondToRequest(id: id, result: nil, error: error.localizedDescription, tab: tab)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Task { @MainActor in
            tab?.isLoading = true
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let tab = tab else { return }
            tab.isLoading = false
            tab.url = webView.url
            tab.title = webView.title ?? webView.url?.host ?? "New Tab"
            tab.canGoBack = webView.canGoBack
            tab.canGoForward = webView.canGoForward
            tab.isSecure = webView.url?.scheme == "https"

            // Re-announce provider
            if let address = browserModel?.connectedAddress {
                let js = """
                if (window._ethWalletEvent) { window._ethWalletEvent('accountsChanged', ['\(address.lowercased())']); }
                if (window.dispatchEvent && window.ethereum) {
                    window.dispatchEvent(new CustomEvent('eip6963:announceProvider', {
                        detail: Object.freeze({ info: { uuid: 'ethwallet-provider-001', name: 'EthWallet', icon: '', rdns: 'app.ethwallet' }, provider: window.ethereum })
                    }));
                }
                """
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            tab?.isLoading = false
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let host = url.host?.lowercased() ?? ""
            let blockedDomains = ["google-analytics.com", "googletagmanager.com", "facebook.net", "doubleclick.net"]
            for blocked in blockedDomains {
                if host.contains(blocked) {
                    decisionHandler(.cancel)
                    return
                }
            }
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate (handle target="_blank" / window.open)

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Open in new tab instead of external window
        Task { @MainActor in
            if let url = navigationAction.request.url {
                _ = browserModel?.createTab(url: url)
            }
        }
        return nil // Return nil so WKWebView doesn't try to create its own window
    }
}

// MARK: - Browser View

struct BrowserView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel
    @StateObject private var browserModel = BrowserViewModel()

    @State private var urlText = ""
    @State private var showingSignSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            tabBar

            Divider()

            // Toolbar
            browserToolbar

            Divider()

            // Web content
            WebViewContainer(browserModel: browserModel)
        }
        .sheet(isPresented: $showingSignSheet, onDismiss: {
            // If dismissed without action, reject the request
            if let request = browserModel.pendingSignRequest, let tab = browserModel.pendingSignTab {
                browserModel.respondToRequest(id: request.id, result: nil, error: "User rejected", tab: tab)
            }
            browserModel.pendingSignRequest = nil
            browserModel.pendingSignTab = nil
        }) {
            if let request = browserModel.pendingSignRequest, let tab = browserModel.pendingSignTab {
                BrowserSignSheet(
                    request: request,
                    walletViewModel: walletViewModel,
                    onApprove: { result in
                        print("[Browser] onApprove called, result type=\(type(of: result)), id=\(request.id)")
                        browserModel.respondToRequest(id: request.id, result: result, error: nil, tab: tab)
                        browserModel.pendingSignRequest = nil
                        browserModel.pendingSignTab = nil
                        showingSignSheet = false
                    },
                    onReject: {
                        print("[Browser] onReject called, id=\(request.id)")
                        browserModel.respondToRequest(id: request.id, result: nil, error: "User rejected", tab: tab)
                        browserModel.pendingSignRequest = nil
                        browserModel.pendingSignTab = nil
                        showingSignSheet = false
                    }
                )
            }
        }
        .onChange(of: browserModel.pendingSignRequest?.id) { _, newValue in
            if newValue != nil {
                showingSignSheet = true
            }
        }
        .onAppear {
            if browserModel.tabs.isEmpty {
                _ = browserModel.createTab()
            }
            if let address = walletViewModel.selectedAccount?.address {
                browserModel.setAccount(address)
            }
        }
        .onChange(of: walletViewModel.selectedAccount) { _, newAccount in
            if let address = newAccount?.address {
                browserModel.setAccount(address)
            }
        }
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(browserModel.tabs) { tab in
                        tabButton(for: tab)
                    }
                }
            }

            Divider().frame(height: 28)

            // New tab button
            Button(action: {
                _ = browserModel.createTab()
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)

            // Connected indicator
            if walletViewModel.selectedAccount != nil {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                    Text(walletViewModel.selectedAccount?.address.prefix(6) ?? "")
                        .font(.system(size: 10).monospaced())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(4)
                .padding(.trailing, 8)
            }
        }
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func tabButton(for tab: BrowserTab) -> some View {
        let isActive = tab.id == browserModel.activeTabId

        HStack(spacing: 6) {
            if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            }

            Text(tab.title)
                .font(.system(size: 11))
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)

            if browserModel.tabs.count > 1 {
                Button(action: { browserModel.closeTab(tab.id) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: isActive ? 2 : 0)
                .foregroundStyle(.blue),
            alignment: .bottom
        )
        .onTapGesture {
            browserModel.activeTabId = tab.id
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var browserToolbar: some View {
        HStack(spacing: 10) {
            Button(action: { browserModel.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!(browserModel.activeTab?.canGoBack ?? false))
            .buttonStyle(.borderless)

            Button(action: { browserModel.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!(browserModel.activeTab?.canGoForward ?? false))
            .buttonStyle(.borderless)

            Button(action: { browserModel.reload() }) {
                Image(systemName: (browserModel.activeTab?.isLoading ?? false) ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            // URL bar
            HStack(spacing: 6) {
                if browserModel.activeTab?.isSecure == true {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                }

                TextField("Search or enter URL", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        browserModel.navigate(to: urlText)
                    }

                Button(action: { browserModel.navigate(to: urlText) }) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(urlText.isEmpty)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)

            Button(action: { browserModel.goHome() }) {
                Image(systemName: "house")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .onChange(of: browserModel.activeTab?.url) { _, newURL in
            if let url = newURL {
                urlText = url.absoluteString
            }
        }
        .onChange(of: browserModel.activeTabId) { _, _ in
            if let url = browserModel.activeTab?.url {
                urlText = url.absoluteString
            }
        }
    }
}

// MARK: - WebView Container

struct WebViewContainer: NSViewRepresentable {
    @ObservedObject var browserModel: BrowserViewModel

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let activeTab = browserModel.activeTab else { return }
        let webView = activeTab.webView

        // Only swap if needed
        if container.subviews.first !== webView {
            container.subviews.forEach { $0.removeFromSuperview() }
            webView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: container.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
    }
}

// MARK: - Web3 Request Model

struct Web3Request: Identifiable {
    let id: Double
    let method: String
    let params: [Any]
}

// MARK: - Embedded Provider Script (fallback if .js file not in bundle)

enum Web3ProviderScript {
    static let source = """
    (function() {
        'use strict';
        if (window.ethereum && window.ethereum.isEthWallet) return;

        let selectedAddress = null;
        let chainId = null;
        let isConnected = false;
        const eventListeners = {};

        function emit(event, data) {
            if (eventListeners[event]) {
                eventListeners[event].forEach(cb => { try { cb(data); } catch(e) {} });
            }
        }

        function sendToNative(method, params) {
            return new Promise((resolve, reject) => {
                const id = Date.now() + Math.random();
                window._ethWalletCallbacks = window._ethWalletCallbacks || {};
                window._ethWalletCallbacks[id] = { resolve, reject };
                window.webkit.messageHandlers.ethWallet.postMessage({ id, method, params: params || [] });
            });
        }

        window._ethWalletResponse = function(id, result, error) {
            const cb = window._ethWalletCallbacks[id];
            if (cb) {
                error ? cb.reject(new Error(error)) : cb.resolve(result);
                delete window._ethWalletCallbacks[id];
            }
        };

        window._ethWalletEvent = function(event, data) {
            if (event === 'accountsChanged') { selectedAddress = data[0] || null; emit('accountsChanged', data); }
            else if (event === 'chainChanged') { chainId = data; emit('chainChanged', data); }
            else if (event === 'connect') { isConnected = true; emit('connect', { chainId }); }
            else if (event === 'disconnect') { isConnected = false; selectedAddress = null; emit('disconnect', { code: 4900, message: 'Disconnected' }); }
        };

        async function initChainId() {
            try { const id = await sendToNative('eth_chainId', []); if (id) chainId = id; } catch(e) { chainId = '0x1'; }
        }

        const ethereum = {
            isEthWallet: true,
            isMetaMask: true,
            get chainId() { return chainId; },
            get selectedAddress() { return selectedAddress; },
            get connected() { return isConnected; },
            isConnected() { return isConnected; },

            async request({ method, params }) {
                if (!chainId && method !== 'eth_chainId') await initChainId();
                if (method === 'eth_requestAccounts') {
                    const accounts = await sendToNative(method, params);
                    if (accounts && accounts.length > 0) { selectedAddress = accounts[0]; isConnected = true; emit('connect', { chainId }); emit('accountsChanged', accounts); }
                    return accounts;
                }
                if (method === 'eth_accounts') { return selectedAddress ? [selectedAddress] : await sendToNative(method, params); }
                if (method === 'eth_chainId') { if (!chainId) await initChainId(); return chainId || '0x1'; }
                if (method === 'net_version') { if (!chainId) await initChainId(); return parseInt(chainId || '0x1', 16).toString(); }
                if (method === 'wallet_requestPermissions') return [{ parentCapability: 'eth_accounts' }];
                if (method === 'wallet_getPermissions') return selectedAddress ? [{ parentCapability: 'eth_accounts' }] : [];
                return await sendToNative(method, params);
            },

            async enable() { return this.request({ method: 'eth_requestAccounts' }); },
            async send(m, p) {
                if (typeof m === 'string') return this.request({ method: m, params: p });
                if (typeof p === 'function') { try { const r = await this.request(m); p(null, { id: m.id, jsonrpc: '2.0', result: r }); } catch(e) { p(e); } }
                else return this.request(m);
            },
            sendAsync(payload, cb) {
                this.request({ method: payload.method, params: payload.params })
                    .then(r => cb(null, { id: payload.id, jsonrpc: '2.0', result: r }))
                    .catch(e => cb(e));
            },

            on(event, cb) { if (!eventListeners[event]) eventListeners[event] = []; eventListeners[event].push(cb); return this; },
            removeListener(event, cb) { if (eventListeners[event]) { const i = eventListeners[event].indexOf(cb); if (i > -1) eventListeners[event].splice(i, 1); } return this; },
            removeAllListeners(event) { event ? delete eventListeners[event] : Object.keys(eventListeners).forEach(k => delete eventListeners[k]); return this; },

            autoRefreshOnNetworkChange: false,
            _metamask: { isUnlocked: async () => true }
        };

        Object.defineProperty(window, 'ethereum', { value: ethereum, writable: false, configurable: false });

        const providerDetail = Object.freeze({ info: { uuid: 'ethwallet-provider-001', name: 'EthWallet', icon: '', rdns: 'app.ethwallet' }, provider: ethereum });
        function announceProvider() { window.dispatchEvent(new CustomEvent('eip6963:announceProvider', { detail: providerDetail })); }
        window.addEventListener('eip6963:requestProvider', announceProvider);
        announceProvider();
        window.dispatchEvent(new Event('ethereum#initialized'));
        initChainId();
        console.log('EthWallet: Web3 provider injected (EIP-1193 + EIP-6963)');
    })();
    """
}

#Preview {
    BrowserView()
        .environmentObject(WalletViewModel())
}
