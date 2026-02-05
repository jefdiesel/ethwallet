// EIP-1193 Ethereum Provider + EIP-6963 Wallet Discovery
// Injected into web pages to enable dApp connectivity

(function() {
    'use strict';

    // Prevent double injection
    if (window.ethereum && window.ethereum.isEthWallet) {
        return;
    }

    let selectedAddress = null;
    let chainId = null; // Will be fetched from native
    let isConnected = false;

    // Event emitter
    const eventListeners = {};

    function emit(event, data) {
        if (eventListeners[event]) {
            eventListeners[event].forEach(callback => {
                try {
                    callback(data);
                } catch (e) {
                    console.error('EthWallet: Event listener error', e);
                }
            });
        }
    }

    // Send request to native app
    function sendToNative(method, params) {
        return new Promise((resolve, reject) => {
            const id = Date.now() * 1000 + Math.floor(Math.random() * 1000);

            console.log('EthWallet: sendToNative method=' + method + ' id=' + id);

            // Store callback for response
            window._ethWalletCallbacks = window._ethWalletCallbacks || {};
            window._ethWalletCallbacks[id] = { resolve, reject };

            // Send to native via message handler
            window.webkit.messageHandlers.ethWallet.postMessage({
                id: id,
                method: method,
                params: params || []
            });
        });
    }

    // Handle response from native (supports all JSON types)
    window._ethWalletResponse = function(id, result, error) {
        console.log('EthWallet: _ethWalletResponse id=' + id + ' hasCallback=' + !!(window._ethWalletCallbacks && window._ethWalletCallbacks[id]) + ' pendingIds=' + Object.keys(window._ethWalletCallbacks || {}).join(','));
        const callback = window._ethWalletCallbacks[id];
        if (callback) {
            if (error) {
                callback.reject(new Error(error));
            } else {
                console.log('EthWallet: resolving callback with result type=' + typeof result);
                callback.resolve(result);
            }
            delete window._ethWalletCallbacks[id];
        } else {
            console.warn('EthWallet: NO callback found for id=' + id);
        }
    };

    // Handle events from native
    window._ethWalletEvent = function(event, data) {
        if (event === 'accountsChanged') {
            selectedAddress = data[0] || null;
            emit('accountsChanged', data);
        } else if (event === 'chainChanged') {
            chainId = data;
            emit('chainChanged', data);
        } else if (event === 'connect') {
            isConnected = true;
            emit('connect', { chainId: chainId });
        } else if (event === 'disconnect') {
            isConnected = false;
            selectedAddress = null;
            emit('disconnect', { code: 4900, message: 'Disconnected' });
        }
    };

    // Fetch initial chain ID from native
    async function initChainId() {
        try {
            const id = await sendToNative('eth_chainId', []);
            if (id) chainId = id;
        } catch (e) {
            chainId = '0x1'; // fallback
        }
    }

    // EIP-1193 Provider
    const ethereum = {
        isEthWallet: true,
        isMetaMask: true, // For compatibility with dApps that check for MetaMask

        get chainId() {
            return chainId;
        },

        get selectedAddress() {
            return selectedAddress;
        },

        get connected() {
            return isConnected;
        },

        isConnected() {
            return isConnected;
        },

        // EIP-1193 request method
        async request({ method, params }) {
            // Ensure chainId is loaded
            if (!chainId && method !== 'eth_chainId') {
                await initChainId();
            }

            switch (method) {
                case 'eth_requestAccounts': {
                    const accounts = await sendToNative(method, params);
                    if (accounts && accounts.length > 0) {
                        selectedAddress = accounts[0];
                        isConnected = true;
                        emit('connect', { chainId: chainId });
                        emit('accountsChanged', accounts);
                    }
                    return accounts;
                }

                case 'eth_accounts':
                    // Return cached address if available, no events (avoids infinite loop)
                    if (selectedAddress) return [selectedAddress];
                    return await sendToNative(method, params);

                case 'eth_chainId':
                    if (!chainId) await initChainId();
                    return chainId || '0x1';

                case 'net_version':
                    if (!chainId) await initChainId();
                    return parseInt(chainId || '0x1', 16).toString();

                case 'wallet_switchEthereumChain': {
                    const newChainId = params[0]?.chainId;
                    if (newChainId) {
                        const result = await sendToNative(method, params);
                        chainId = newChainId;
                        emit('chainChanged', newChainId);
                        return result;
                    }
                    throw new Error('Invalid chainId');
                }

                case 'wallet_requestPermissions':
                    // Return granted permissions for eth_accounts
                    return [{ parentCapability: 'eth_accounts' }];

                case 'wallet_getPermissions':
                    if (selectedAddress) {
                        return [{ parentCapability: 'eth_accounts' }];
                    }
                    return [];

                default:
                    // Forward everything else to native
                    return await sendToNative(method, params);
            }
        },

        // Legacy methods for compatibility
        async enable() {
            return this.request({ method: 'eth_requestAccounts' });
        },

        async send(methodOrPayload, paramsOrCallback) {
            // Handle different call signatures
            if (typeof methodOrPayload === 'string') {
                return this.request({ method: methodOrPayload, params: paramsOrCallback });
            } else if (typeof paramsOrCallback === 'function') {
                // Callback style
                try {
                    const result = await this.request(methodOrPayload);
                    paramsOrCallback(null, { id: methodOrPayload.id, jsonrpc: '2.0', result });
                } catch (error) {
                    paramsOrCallback(error);
                }
            } else {
                return this.request(methodOrPayload);
            }
        },

        sendAsync(payload, callback) {
            this.request({ method: payload.method, params: payload.params })
                .then(result => callback(null, { id: payload.id, jsonrpc: '2.0', result }))
                .catch(error => callback(error));
        },

        // Event handling
        on(event, callback) {
            if (!eventListeners[event]) {
                eventListeners[event] = [];
            }
            eventListeners[event].push(callback);
            return this;
        },

        removeListener(event, callback) {
            if (eventListeners[event]) {
                const index = eventListeners[event].indexOf(callback);
                if (index > -1) {
                    eventListeners[event].splice(index, 1);
                }
            }
            return this;
        },

        removeAllListeners(event) {
            if (event) {
                delete eventListeners[event];
            } else {
                Object.keys(eventListeners).forEach(key => delete eventListeners[key]);
            }
            return this;
        },

        // Deprecated but still used by some dApps
        autoRefreshOnNetworkChange: false,
        _metamask: {
            isUnlocked: async () => true
        }
    };

    // Make it non-writable to prevent dApps from overwriting
    Object.defineProperty(window, 'ethereum', {
        value: ethereum,
        writable: false,
        configurable: false
    });

    // ---- EIP-6963: Multi-wallet discovery ----

    const providerInfo = {
        uuid: 'ethwallet-provider-001',
        name: 'EthWallet',
        icon: 'data:image/svg+xml;base64,' + btoa('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128"><rect width="128" height="128" rx="24" fill="#627EEA"/><path d="M64 16l-1.3 4.4V81l1.3 1.2 29-17.1z" fill="#fff" opacity=".6"/><path d="M64 16L35 65.1l29 17.1V16z" fill="#fff"/><path d="M64 89.3l-.7.9v22.2l.7 2.1L93 72.2z" fill="#fff" opacity=".6"/><path d="M64 114.5V89.3L35 72.2z" fill="#fff"/></svg>'),
        rdns: 'app.ethwallet'
    };

    const providerDetail = Object.freeze({ info: providerInfo, provider: ethereum });

    function announceProvider() {
        window.dispatchEvent(new CustomEvent('eip6963:announceProvider', { detail: providerDetail }));
    }

    // Announce on request
    window.addEventListener('eip6963:requestProvider', announceProvider);

    // Announce immediately
    announceProvider();

    // Also fire the legacy event
    window.dispatchEvent(new Event('ethereum#initialized'));

    // Initialize chain ID in background
    initChainId();

    console.log('EthWallet: Web3 provider injected (EIP-1193 + EIP-6963)');
})();
