import Foundation
import AppKit
import Combine

/// Checks the GitHub Releases feed for a newer version, and can download the
/// new DMG and open it so the user finishes the update with one drag.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let repoSlug = "michaelmax98/BatteryWatts"

    @Published private(set) var availableVersion: String?
    @Published private(set) var releasePage: URL?
    @Published private(set) var dmgURL: URL?
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var statusMessage: String?

    /// nil when running unbundled via `swift run`; updates are disabled then.
    var currentVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var timer: Timer?

    private init() {
        guard currentVersion != nil else { return }
        let timer = Timer(timeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.check(userInitiated: false)
        }
    }

    deinit {
        timer?.invalidate()
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let html_url: String
        let assets: [Asset]
    }

    func check(userInitiated: Bool) {
        guard let current = currentVersion, !isChecking,
              let url = URL(string: "https://api.github.com/repos/\(Self.repoSlug)/releases/latest") else { return }
        DispatchQueue.main.async {
            self.isChecking = true
            if userInitiated { self.statusMessage = nil }
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            var newVersion: String?
            var page: URL?
            var dmg: URL?
            var message: String?
            if let data, let release = try? JSONDecoder().decode(Release.self, from: data) {
                let latest = release.tag_name.hasPrefix("v")
                    ? String(release.tag_name.dropFirst())
                    : release.tag_name
                if Self.isVersion(latest, newerThan: current) {
                    newVersion = latest
                    page = URL(string: release.html_url)
                    if let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) {
                        dmg = URL(string: asset.browser_download_url)
                    }
                } else if userInitiated {
                    message = "You're up to date (v\(current))."
                }
            } else if userInitiated {
                message = "Couldn't check for updates — try again later."
            }
            DispatchQueue.main.async {
                self.isChecking = false
                self.availableVersion = newVersion
                self.releasePage = page
                self.dmgURL = dmg
                if let message { self.statusMessage = message }
            }
        }.resume()
    }

    func downloadAndOpenUpdate() {
        guard let downloadURL = dmgURL else {
            if let releasePage { NSWorkspace.shared.open(releasePage) }
            return
        }
        DispatchQueue.main.async {
            self.isDownloading = true
            self.statusMessage = nil
        }
        URLSession.shared.downloadTask(with: downloadURL) { [weak self] tempURL, _, _ in
            guard let self else { return }
            var opened = false
            if let tempURL,
               let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                let dest = downloads.appendingPathComponent(downloadURL.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.moveItem(at: tempURL, to: dest)) != nil {
                    NSWorkspace.shared.open(dest)
                    opened = true
                }
            }
            DispatchQueue.main.async {
                self.isDownloading = false
                if opened {
                    self.statusMessage = "Update opened — drag BatteryWatts to Applications, then relaunch."
                } else {
                    self.statusMessage = "Download failed — opening the releases page instead."
                    if let releasePage = self.releasePage {
                        NSWorkspace.shared.open(releasePage)
                    }
                }
            }
        }.resume()
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
