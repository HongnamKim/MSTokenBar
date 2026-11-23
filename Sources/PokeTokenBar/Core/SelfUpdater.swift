import Foundation
import Security

/// Installs a release zip in place: download → unzip → verify → swap the bundle after the app quits → reopen.
/// Used while there is no Homebrew cask. Any failure returns nil/false so the caller can open the release page.
enum SelfUpdater {
    static let assetName = "MSTokenBar.zip"
    static let repoPath = "/HongnamKim/MSTokenBar/releases/download/"

    /// Only this repository's release assets may be downloaded and installed.
    static func isTrustedAssetURL(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme == "https", url.host == "github.com" else { return false }
        return url.path.hasPrefix(repoPath) && url.lastPathComponent == assetName
    }

    /// `MSTokenBar.zip` download URL from a GitHub release payload, or nil.
    static func zipURL(fromAssets assets: Any?) -> String? {
        guard let assets = assets as? [[String: Any]] else { return nil }
        return assets.first { $0["name"] as? String == assetName }?["browser_download_url"] as? String
    }

    /// Downloads and unzips the release, then checks the app inside. Returns the verified bundle URL.
    static func prepare(zipURL: String, expectedVersion: String,
                        current: Bundle = .main) async -> URL? {
        guard isTrustedAssetURL(zipURL), let url = URL(string: zipURL) else { return nil }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("mstokenbar-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            var request = URLRequest(url: url, timeoutInterval: 120)
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            let (download, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw CocoaError(.fileReadUnknown) }
            let zip = work.appendingPathComponent(assetName)
            try FileManager.default.moveItem(at: download, to: zip)
            let unzipped = work.appendingPathComponent("unzipped", isDirectory: true)
            guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unzipped.path]) else { throw CocoaError(.fileReadCorruptFile) }
            let app = unzipped.appendingPathComponent(current.bundleURL.lastPathComponent)
            guard verify(app: app, expectedVersion: expectedVersion, current: current) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return app
        } catch {
            AppLog.write("update: self-update download/verify failed — \(error)")
            try? FileManager.default.removeItem(at: work)
            return nil
        }
    }

    /// Same bundle id, the announced version, and a valid signature that satisfies **this** app's
    /// designated requirement (same signing certificate). An ad-hoc dev build's requirement is its own
    /// cdhash, so it never accepts a release — such builds fall back to the release page.
    static func verify(app: URL, expectedVersion: String, current: Bundle = .main) -> Bool {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let currentID = current.bundleIdentifier,
              info["CFBundleIdentifier"] as? String == currentID,
              info["CFBundleShortVersionString"] as? String == expectedVersion,
              let requirement = currentDesignatedRequirement(of: current) else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess
    }

    private static func currentDesignatedRequirement(of bundle: Bundle) -> SecRequirement? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle.bundleURL as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    /// The bundle can be swapped only when its folder is writable (e.g. /Applications for an admin user).
    static func canReplace(bundle: Bundle = .main) -> Bool {
        FileManager.default.isWritableFile(atPath: bundle.bundleURL.deletingLastPathComponent().path)
    }

    /// Detached script run after the app quits. Positional args — no shell interpolation:
    /// $1 = verified new app, $2 = installed bundle path, $3 = app pid, $4 = work dir to delete,
    /// $5 = opener (`/usr/bin/open`; tests pass `/usr/bin/true`).
    /// The old bundle is kept aside until the copy succeeds, and restored if it fails.
    static let detachedReplaceScript = """
    for i in $(seq 1 40); do kill -0 "$3" 2>/dev/null || break; sleep 0.5; done
    backup="$2.update-backup"
    rm -rf "$backup"
    if mv "$2" "$backup"; then
      if /usr/bin/ditto "$1" "$2"; then
        rm -rf "$backup"
      else
        rm -rf "$2"
        mv "$backup" "$2"
      fi
    fi
    rm -rf "$4"
    for i in $(seq 1 15); do
      "$5" "$2" 2>/dev/null && break
      sleep 1
    done
    """

    @discardableResult
    static func launchDetachedReplace(newApp: URL, bundlePath: String = Bundle.main.bundlePath,
                                      pid: pid_t = ProcessInfo.processInfo.processIdentifier,
                                      opener: String = "/usr/bin/open") -> Process? {
        let workDir = newApp.deletingLastPathComponent().deletingLastPathComponent()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", detachedReplaceScript, "sh", newApp.path, bundlePath, String(pid), workDir.path, opener]
        do { try task.run() } catch { return nil }
        return task
    }

    private static func run(_ binary: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
