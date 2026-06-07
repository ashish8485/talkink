import Foundation
import Combine
import AppKit

struct UpdateInfo: Equatable {
    let version: String
    let url: URL
    let notes: String
}

/// Lightweight update notifier: checks the GitHub Releases API and, if a newer
/// version is published, surfaces a "new version available" affordance.
/// (Full auto-install via Sparkle is a later step, once releases are notarized.)
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let repo = "hasso5703/soyle"

    @Published var latest: UpdateInfo?     // set only when strictly newer than current
    @Published var checking = false
    @Published var checkedOnce = false

    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    func check() {
        guard !checking,
              let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")
        else { return }
        checking = true
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async { self?.handle(data) }
        }.resume()
    }

    private func handle(_ data: Data?) {
        checking = false
        checkedOnce = true
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let htmlURL = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return }   // no releases yet / offline / rate-limited → stay silent
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        if Self.isNewer(v, than: currentVersion) {
            latest = UpdateInfo(version: v, url: htmlURL, notes: (json["body"] as? String) ?? "")
        }
    }

    /// Numeric, component-wise semver compare ("0.2.0" > "0.1.3").
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
