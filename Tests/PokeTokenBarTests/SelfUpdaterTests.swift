import Foundation
import XCTest
@testable import PokeTokenBar

final class SelfUpdaterTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("self-updater-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: release asset

    func testOnlyThisRepositorysZipAssetIsTrusted() {
        XCTAssertTrue(SelfUpdater.isTrustedAssetURL(
            "https://github.com/HongnamKim/MSTokenBar/releases/download/v0.1.1/MSTokenBar.zip"))
        for url in ["http://github.com/HongnamKim/MSTokenBar/releases/download/v0.1.1/MSTokenBar.zip",
                    "https://evil.example/HongnamKim/MSTokenBar/releases/download/v0.1.1/MSTokenBar.zip",
                    "https://github.com/chattymin/PokeTokenBar/releases/download/v2.5.7/PokeTokenBar.zip",
                    "https://github.com/HongnamKim/MSTokenBar/releases/download/v0.1.1/Other.zip",
                    "https://github.com/HongnamKim/MSTokenBar/archive/refs/tags/v0.1.1.zip"] {
            XCTAssertFalse(SelfUpdater.isTrustedAssetURL(url), url)
        }
    }

    func testZipAssetIsPickedByName() {
        let assets: [[String: Any]] = [
            ["name": "notes.txt", "browser_download_url": "https://github.com/x/notes.txt"],
            ["name": "MSTokenBar.zip",
             "browser_download_url": "https://github.com/HongnamKim/MSTokenBar/releases/download/v0.1.1/MSTokenBar.zip"],
        ]
        XCTAssertEqual(SelfUpdater.zipURL(fromAssets: assets),
                       "https://github.com/HongnamKim/MSTokenBar/releases/download/v0.1.1/MSTokenBar.zip")
        XCTAssertNil(SelfUpdater.zipURL(fromAssets: nil))
        XCTAssertNil(SelfUpdater.zipURL(fromAssets: [["name": "Other.zip"]]))
    }

    @MainActor
    func testUntrustedZipURLIsDroppedFromTheOffer() {
        let checker = UpdateChecker(currentVersion: "0.1.0", defaults: UserDefaults(suiteName: "SelfUpdater-\(UUID())")!,
                                    fetchLatest: { nil })
        checker.consider(latest: "0.1.1", url: "https://github.com/HongnamKim/MSTokenBar/releases/tag/v0.1.1",
                         zipURL: "https://evil.example/MSTokenBar.zip")
        XCTAssertEqual(checker.available?.version, "0.1.1")
        XCTAssertNil(checker.available?.zipURL, "an untrusted asset must never be downloaded")

        let trusted = "https://github.com/HongnamKim/MSTokenBar/releases/download/v0.1.1/MSTokenBar.zip"
        checker.consider(latest: "0.1.1", url: "https://github.com/HongnamKim/MSTokenBar/releases/tag/v0.1.1",
                         zipURL: trusted)
        XCTAssertEqual(checker.available?.zipURL, trusted)
    }

    // MARK: signature check

    /// A copy of the running app's own signed bundle is accepted; changed contents are not.
    func testVerifyAcceptsOnlyTheSameSignature() throws {
        let installed = try makeSignedApp(named: "Installed", version: "0.1.0")
        let current = try XCTUnwrap(Bundle(url: installed))

        // Same signed bytes, as a release built with the same certificate would satisfy the requirement.
        let sameSigner = root.appendingPathComponent("same/Fake.app")
        try FileManager.default.createDirectory(at: sameSigner.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: installed, to: sameSigner)
        XCTAssertTrue(SelfUpdater.verify(app: sameSigner, expectedVersion: "0.1.0", current: current))
        XCTAssertFalse(SelfUpdater.verify(app: sameSigner, expectedVersion: "0.1.1", current: current),
                       "the version must match the release that was offered")

        // Ad-hoc signatures pin the exact code, so a different build fails the installed app's requirement.
        let other = try makeSignedApp(named: "Other", version: "0.1.0", marker: "different")
        XCTAssertFalse(SelfUpdater.verify(app: other, expectedVersion: "0.1.0", current: current))

        // Tampering after signing breaks the seal.
        try Data("tampered".utf8).write(to: sameSigner.appendingPathComponent("Contents/Resources/marker.txt"))
        XCTAssertFalse(SelfUpdater.verify(app: sameSigner, expectedVersion: "0.1.0", current: current))
    }

    // MARK: detached swap

    func testReplaceScriptSwapsTheBundleAndCleansUp() throws {
        let installed = try makePlainApp(at: root.appendingPathComponent("Applications/Fake.app"), marker: "old")
        let work = root.appendingPathComponent("work", isDirectory: true)
        let newApp = try makePlainApp(at: work.appendingPathComponent("unzipped/Fake.app"), marker: "new")

        try runReplace(newApp: newApp, installed: installed)

        XCTAssertEqual(try marker(installed), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path + ".update-backup"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: work.path), "the download folder is removed")
    }

    func testReplaceScriptRestoresTheOldAppWhenTheCopyFails() throws {
        let installed = try makePlainApp(at: root.appendingPathComponent("Applications/Fake.app"), marker: "old")
        let missing = root.appendingPathComponent("work/unzipped/Fake.app")   // never created → ditto fails

        try runReplace(newApp: missing, installed: installed)

        XCTAssertEqual(try marker(installed), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path + ".update-backup"))
    }

    // MARK: helpers

    private func runReplace(newApp: URL, installed: URL) throws {
        // A pid that no longer exists, so the script does not wait for the app to quit.
        let finished = Process()
        finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try finished.run()
        finished.waitUntilExit()
        let task = try XCTUnwrap(SelfUpdater.launchDetachedReplace(
            newApp: newApp, bundlePath: installed.path, pid: finished.processIdentifier, opener: "/usr/bin/true"))
        task.waitUntilExit()
        XCTAssertEqual(task.terminationStatus, 0)
    }

    @discardableResult
    private func makePlainApp(at url: URL, marker: String, version: String = "0.1.0") throws -> URL {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "io.github.hongnamkim.mstokenbar.test",
                                   "CFBundleShortVersionString": version, "CFBundleVersion": version,
                                   "CFBundleExecutable": "Fake", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                         to: contents.appendingPathComponent("MacOS/Fake"))
        try Data(marker.utf8).write(to: contents.appendingPathComponent("Resources/marker.txt"))
        return url
    }

    private func makeSignedApp(named folder: String, version: String, marker: String = "same") throws -> URL {
        let app = try makePlainApp(at: root.appendingPathComponent("\(folder)/Fake.app"), marker: marker, version: version)
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--deep", "--sign", "-", app.path]
        sign.standardError = FileHandle.nullDevice
        try sign.run()
        sign.waitUntilExit()
        XCTAssertEqual(sign.terminationStatus, 0, "ad-hoc signing the fixture")
        return app
    }

    private func marker(_ app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("Contents/Resources/marker.txt"), encoding: .utf8)
    }
}
