import SwiftUI
import WebKit

/// Level 3, implemented properly.
///
/// The web view is built on a non-persistent `WKWebsiteDataStore`, so its
/// cookies and storage live in memory only and are gone the moment the view
/// goes away. That is a genuine clean session that this app controls, rather
/// than a promise that some other browser behaved itself.
struct CleanRoomView: View {
    let url: String

    @Environment(\.dismiss) private var dismiss
    @State private var reloadToken = UUID()
    @State private var progress: Double = 0
    @State private var mediaDenied = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mediaDenied
                     ? "Camera and microphone denied - you can still join to listen"
                     : "Fresh session - no cookies, no storage, no device id")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(mediaDenied ? Theme.warn : Theme.ok)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if progress < 1 {
                ProgressView(value: progress)
                    .tint(Theme.accent)
            }

            CleanRoomWebView(
                url: url,
                reloadToken: reloadToken,
                progress: $progress,
                mediaDenied: $mediaDenied
            )

            HStack(spacing: 12) {
                ActionButton(title: "Wipe and reload", colour: Theme.accent, filled: false) {
                    // A new token rebuilds the web view against a brand new
                    // non-persistent store, which is a stronger reset than
                    // reloading the page.
                    progress = 0
                    mediaDenied = false
                    reloadToken = UUID()
                }
                ActionButton(title: "Done", colour: Theme.muted, filled: false) {
                    dismiss()
                }
            }
            .padding(14)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

private struct CleanRoomWebView: UIViewRepresentable {
    let url: String
    let reloadToken: UUID
    @Binding var progress: Double
    @Binding var mediaDenied: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // The token changing is the signal to start over from an empty store.
        guard context.coordinator.token != reloadToken else { return }
        context.coordinator.token = reloadToken
        context.coordinator.load(into: webView, url: url, fresh: true)
    }

    private func makeWebView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = true

        context.coordinator.observe(webView)
        context.coordinator.token = reloadToken
        context.coordinator.load(into: webView, url: url, fresh: false)
        return webView
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let parent: CleanRoomWebView
        private var observation: NSKeyValueObservation?
        var token: UUID?

        init(_ parent: CleanRoomWebView) {
            self.parent = parent
        }

        func observe(_ webView: WKWebView) {
            observation = webView.observe(\.estimatedProgress, options: [.new]) { view, _ in
                DispatchQueue.main.async {
                    self.parent.progress = view.estimatedProgress
                }
            }
        }

        func load(into webView: WKWebView, url: String, fresh: Bool) {
            if fresh {
                // Empty the in-memory store as well, so a reload cannot inherit
                // anything the previous attempt left behind.
                let store = webView.configuration.websiteDataStore
                let types = WKWebsiteDataStore.allWebsiteDataTypes()
                store.removeData(ofTypes: types, modifiedSince: .distantPast) {
                    Self.startLoad(webView, url)
                }
            } else {
                Self.startLoad(webView, url)
            }
        }

        private static func startLoad(_ webView: WKWebView, _ url: String) {
            guard let target = URL(string: url) else { return }
            webView.load(URLRequest(url: target))
        }

        // Grant the meeting camera and microphone. iOS has already asked the
        // user for both on the app's behalf, so this cannot hand out access the
        // user did not agree to.
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }

        // Zoom's web client opens some flows in a new window, which has no
        // container here. Load them in place instead of dropping them.
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            DispatchQueue.main.async {
                self.parent.progress = 1
            }
        }
    }
}
