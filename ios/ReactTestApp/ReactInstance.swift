//
// Copyright (c) Microsoft Corporation. All rights reserved.
//
// This source code is licensed under the MIT license found in the
// LICENSE file in the root directory of this source tree.
//

import Foundation

final class ReactInstance: NSObject, RCTBridgeDelegate {
    public static let scanForQRCodeNotification =
        NSNotification.Name("ReactInstance.scanForQRCodeNotification")

    static func jsBundleURL() -> URL? {
        RCTBundleURLProvider.sharedSettings().jsBundleURL(
            forBundleRoot: "index",
            fallbackResource: nil
        )
    }

    var remoteBundleURL: URL? {
        didSet {
            initReact(onDidInitialize: { /* noop */ })
        }
    }

    private(set) var bridge: RCTBridge?

    override init() {
        #if DEBUG
            remoteBundleURL = ReactInstance.jsBundleURL()
        #endif

        super.init()

        // Turbo Modules is incompatible with remote JS debugging
        RCTEnableTurboModule(false)

        RCTSetFatalHandler { (error: Error?) in
            guard let error = error else {
                print("Unknown error")
                return
            }

            guard let nsError = error as NSError? else {
                print(error.localizedDescription)
                return
            }

            let message = RCTFormatError(
                nsError.localizedDescription,
                nsError.userInfo[RCTJSStackTraceKey] as? [[String: Any]],
                9001
            )
            print(message ?? nsError.localizedDescription)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onJavaScriptLoading(_:)),
            name: .RCTJavaScriptWillStartLoading,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onJavaScriptLoaded(_:)),
            name: .RCTJavaScriptDidLoad,
            object: nil
        )

        #if os(iOS)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(onRemoteBundleURLReceived(_:)),
                name: .didReceiveRemoteBundleURL,
                object: nil
            )
        #endif

        #if USE_FLIPPER
            if let flipper = FlipperClient.shared() {
                flipper.add(FlipperKitLayoutPlugin(
                    rootNode: UIApplication.shared,
                    with: SKDescriptorMapper()
                ))
                flipper.add(FKUserDefaultsPlugin(suiteName: nil))
                flipper.add(FlipperKitReactPlugin())
                flipper.add(FlipperKitNetworkPlugin(networkAdapter: SKIOSNetworkAdapter()))
                flipper.start()
            }
        #endif
    }

    init(forTestingPurposesOnly: Bool) {
        assert(forTestingPurposesOnly)
    }

    func initReact(onDidInitialize: @escaping () -> Void) {
        if let bridge = bridge {
            if remoteBundleURL == nil {
                // When loading the embedded bundle, we must disable remote
                // debugging to prevent the bridge from getting stuck in
                // -[RCTWebSocketExecutor executeApplicationScript:sourceURL:onComplete:]
                RCTDevSettings().isDebuggingRemotely = false
            }
            RTATriggerReloadCommand(bridge, "ReactTestApp")
        } else if let bridge = RCTBridge(delegate: self, launchOptions: nil) {
            self.bridge = bridge

            NotificationCenter.default.post(
                name: .ReactTestAppDidInitialize,
                object: bridge
            )

            onDidInitialize()
        } else {
            assertionFailure("Failed to instantiate RCTBridge")
        }
    }

    // MARK: - RCTBridgeDelegate details

    func sourceURL(for _: RCTBridge?) -> URL? {
        if let remoteBundleURL = remoteBundleURL {
            return remoteBundleURL
        }

        #if os(iOS)
            let possibleEntryFiles = [
                "index.ios",
                "main.ios",
                "index.mobile",
                "main.mobile",
                "index.native",
                "main.native",
                "index",
                "main",
            ]
        #elseif os(macOS)
            let possibleEntryFiles = [
                "index.macos",
                "main.macos",
                "index.native",
                "main.native",
                "index",
                "main",
            ]
        #endif

        let jsBundleURL = possibleEntryFiles
            .lazy
            .map {
                Bundle.main.url(
                    forResource: $0,
                    withExtension: "jsbundle"
                )
            }
            .first(where: { $0 != nil })
        return jsBundleURL ?? ReactInstance.jsBundleURL()
    }

    func extraModules(for _: RCTBridge!) -> [RCTBridgeModule] {
        []
    }

    // MARK: - Private

    @objc private func onJavaScriptLoaded(_ notification: Notification) {
        guard let bridge = notification.userInfo?["bridge"] as? RCTBridge,
              let currentBundleURL = bridge.bundleURL
        else {
            return
        }

        RCTExecuteOnMainQueue { [weak self] in
            guard let devMenu = bridge.devMenu else {
                return
            }

            devMenu.add(RCTDevMenuItem.buttonItem(
                titleBlock: {
                    currentBundleURL.isFileURL
                        ? "Load From Dev Server"
                        : "Load Embedded JS Bundle"
                },
                handler: {
                    guard let strongSelf = self else {
                        return
                    }

                    if currentBundleURL.isFileURL {
                        strongSelf.remoteBundleURL = ReactInstance.jsBundleURL()
                    } else {
                        strongSelf.remoteBundleURL = nil
                    }
                }
            ))

            #if os(iOS) && !targetEnvironment(simulator)
                devMenu.add(RCTDevMenuItem.buttonItem(withTitle: "Scan QR Code") {
                    NotificationCenter.default.post(
                        name: ReactInstance.scanForQRCodeNotification,
                        object: self
                    )
                })
            #endif
        }
    }

    @objc private func onJavaScriptLoading(_ notification: Notification) {
        guard self.bridge != nil else {
            // This is a cold boot. The bridge will be set in initReact(onDidInitialize:).
            return
        }

        let bridge = notification.userInfo?["bridge"] as? RCTBridge
        if bridge != self.bridge {
            self.bridge = bridge
        }
    }

    @objc private func onRemoteBundleURLReceived(_ notification: Notification) {
        guard let value = notification.userInfo?["value"] as? String,
              var urlComponents = URLComponents(string: value)
        else {
            return
        }

        urlComponents.queryItems = [URLQueryItem(name: "platform", value: "ios")]
        remoteBundleURL = urlComponents.url
    }
}
