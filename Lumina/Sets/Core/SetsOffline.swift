import Foundation

/// What keeps the page offline (docs/release/TRUST.md I5, THREAT-MODEL T3 / S1). The app needs
/// `com.apple.security.network.client` for WebKit to start in the sandbox, so the system doesn't
/// stop the page reaching the network; these three layers do, each on its own:
///
/// - `contentRules`: WebKit's content blocker refuses every load, then lets the page's own schemes
///   through. A scheme nobody listed (http, https, ws, wss, ftp, anything new) is blocked.
/// - `contentSecurityPolicy`: sent with every page file by `SetsSchemeHandler`, so the page's bytes
///   stay the design's. It names where scripts, styles, images, media, fonts and fetches may come
///   from (`lumina:`, `blob:`, `data:`) and allows no frames, plugins or form posts. Workers only
///   from `blob:` (plumbing's thumbnail and measuring workers, made from its own code; their loads
///   meet the same rules). Scripts need 'unsafe-inline' and 'unsafe-eval': Babel compiles the page.
/// - `pageScript`: WebRTC isn't a URL load, so neither layer above covers it (ICE reaches a STUN or
///   TURN server over UDP or TCP). The page has no use for it; its constructors are removed in
///   every frame before any page script runs, and can't be put back.
///
/// Tests/web/webkit.py reads these three literals from this file and runs the page under them
/// (WebKitGTK), with an escape test that tries every channel against a local listener.
nonisolated enum SetsOffline {
    static let contentRules = #"""
    [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^lumina:"},"action":{"type":"ignore-previous-rules"}},
     {"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}},
     {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},
     {"trigger":{"url-filter":"^about:"},"action":{"type":"ignore-previous-rules"}}]
    """#

    static let contentSecurityPolicy = #"""
    default-src 'none'; script-src lumina: 'unsafe-inline' 'unsafe-eval'; style-src lumina: blob: 'unsafe-inline'; img-src lumina: blob: data:; media-src lumina: blob: data:; font-src lumina: blob: data:; connect-src lumina: blob: data:; frame-src 'none'; child-src 'none'; worker-src blob:; object-src 'none'; manifest-src 'none'; base-uri 'none'; form-action 'none'
    """#

    static let pageScript = #"""
    (() => {
      for (const n of ['RTCPeerConnection', 'webkitRTCPeerConnection', 'RTCDataChannel', 'RTCIceCandidate', 'RTCIceTransport',
                       'RTCSessionDescription', 'RTCRtpSender', 'RTCRtpReceiver', 'RTCRtpTransceiver', 'RTCDtlsTransport',
                       'RTCSctpTransport', 'RTCCertificate', 'RTCRtpScriptTransform']) {
        try { Object.defineProperty(window, n, { value: undefined, writable: false, configurable: false, enumerable: false }); } catch (e) {}
      }
    })();
    """#

    /// The response headers every page file is served with.
    static var pageHeaders: [String: String] {
        ["Content-Security-Policy": contentSecurityPolicy, "X-DNS-Prefetch-Control": "off"]
    }
}
