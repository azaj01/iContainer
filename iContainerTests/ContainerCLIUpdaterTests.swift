import XCTest
@testable import iContainer

/// Pure parts of the in-app `container` CLI updater: release asset
/// selection, signature verification rules, install-method detection.
final class ContainerCLIUpdaterTests: XCTestCase {

    private let pkgutilApple = """
    Package "container-1.5.0.pkg":
       Status: signed by a developer certificate issued by Apple for distribution
       Notarization: trusted by the Apple notary service
       Signed with a trusted timestamp on: 2026-09-29 02:47:09 +0000
       Certificate Chain:
        1. Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)
           Expires: 2030-06-04 16:44:29 +0000
        2. Developer ID Certification Authority
        3. Apple Root CA
    """

    func testSignedPackageAssetPrefersVersionedName() {
        let release: [String: Any] = [
            "tag_name": "1.5.0",
            "assets": [
                ["name": "container-installer-unsigned.pkg", "browser_download_url": "https://x/u.pkg", "size": 1],
                ["name": "container-installer-signed.pkg", "browser_download_url": "https://x/generic.pkg", "size": 2],
                ["name": "container-1.5.0-installer-signed.pkg", "browser_download_url": "https://x/v.pkg", "size": 118_045_087],
            ],
        ]
        let asset = ContainerCLIUpdater.signedPackageAsset(in: release)
        XCTAssertEqual(asset?.name, "container-1.5.0-installer-signed.pkg")
        XCTAssertEqual(asset?.url.absoluteString, "https://x/v.pkg")
        XCTAssertEqual(asset?.size, 118_045_087)
    }

    func testSignedPackageAssetFallsBackAndNeverPicksUnsigned() {
        let release: [String: Any] = [
            "tag_name": "9.9.9",
            "assets": [
                ["name": "container-installer-unsigned.pkg", "browser_download_url": "https://x/u.pkg", "size": 1],
                ["name": "container-9.9.9-installer-signed.pkg", "browser_download_url": "https://x/v.pkg", "size": 2],
            ],
        ]
        XCTAssertEqual(ContainerCLIUpdater.signedPackageAsset(in: release)?.name, "container-9.9.9-installer-signed.pkg")
        XCTAssertNil(ContainerCLIUpdater.signedPackageAsset(in: ["tag_name": "1.0.0", "assets": [["name": "container-installer-unsigned.pkg", "browser_download_url": "https://x/u.pkg"]]]))
        XCTAssertNil(ContainerCLIUpdater.signedPackageAsset(in: [:]))
    }

    func testSignerTeamIDAndTrust() {
        XCTAssertEqual(ContainerCLIUpdater.signerTeamID(fromPkgutilOutput: pkgutilApple), "UPBK2H6LZM")
        XCTAssertTrue(ContainerCLIUpdater.isTrustedPackage(spctlExitStatus: 0, pkgutilOutput: pkgutilApple))
        XCTAssertFalse(ContainerCLIUpdater.isTrustedPackage(spctlExitStatus: 3, pkgutilOutput: pkgutilApple), "spctl rejection wins")
        let otherTeam = pkgutilApple.replacingOccurrences(of: "UPBK2H6LZM", with: "ABCDE12345")
        XCTAssertFalse(ContainerCLIUpdater.isTrustedPackage(spctlExitStatus: 0, pkgutilOutput: otherTeam), "pinned team ID")
        XCTAssertFalse(ContainerCLIUpdater.isTrustedPackage(spctlExitStatus: 0, pkgutilOutput: "Package \"x.pkg\":\n   Status: no signature"))
        XCTAssertNil(ContainerCLIUpdater.signerTeamID(fromPkgutilOutput: ""))
    }

    func testDetectInstallMethod() {
        XCTAssertEqual(ContainerCLIUpdater.detectInstallMethod(cliPath: "/usr/local/bin/container"), .package)
        let brew = ContainerCLIUpdater.detectInstallMethod(cliPath: "/opt/homebrew/bin/container")
        switch brew {
        case .homebrew, .unknown: break // depends on whether brew is installed on the test host
        case .package: XCTFail("a /opt/homebrew path must never map to the package method")
        }
        XCTAssertEqual(ContainerCLIUpdater.detectInstallMethod(cliPath: "/Users/demo/bin/container"),
                       FileManager.default.fileExists(atPath: "/usr/local/bin/update-container.sh") ? .package : .unknown)
    }
}
