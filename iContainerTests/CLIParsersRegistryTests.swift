import XCTest
@testable import iContainer

/// Tests for the registry-related parsers in `CLIParsers`.
final class CLIParsersRegistryTests: XCTestCase {

    // MARK: - parseRegistryHosts

    func testParseRegistryHostsEmpty() {
        XCTAssertEqual(CLIParsers.parseRegistryHosts(""), [])
    }

    func testParseRegistryHostsSkipsHeader() {
        let output = """
        Hostname            Username
        docker.io           alice
        ghcr.io             alice
        """
        XCTAssertEqual(CLIParsers.parseRegistryHosts(output), ["docker.io", "ghcr.io"])
    }

    func testParseRegistryHostsSingleColumn() {
        let output = """
        docker.io
        registry.example.com
        """
        XCTAssertEqual(
            CLIParsers.parseRegistryHosts(output),
            ["docker.io", "registry.example.com"]
        )
    }

    func testParseRegistryHostsIgnoresBlankLines() {
        let output = """

        docker.io

        ghcr.io

        """
        XCTAssertEqual(CLIParsers.parseRegistryHosts(output), ["docker.io", "ghcr.io"])
    }

    // MARK: - registryLoginHosts

    func testRegistryLoginHostsExpandsDockerIO() {
        XCTAssertEqual(
            CLIParsers.registryLoginHosts(for: "docker.io"),
            ["registry-1.docker.io", "docker.io", "index.docker.io"]
        )
    }

    func testRegistryLoginHostsExpandsRegistry1() {
        XCTAssertEqual(
            CLIParsers.registryLoginHosts(for: "registry-1.docker.io"),
            ["registry-1.docker.io", "docker.io", "index.docker.io"]
        )
    }

    func testRegistryLoginHostsExpandsIndex() {
        XCTAssertEqual(
            CLIParsers.registryLoginHosts(for: "index.docker.io"),
            ["registry-1.docker.io", "docker.io", "index.docker.io"]
        )
    }

    func testRegistryLoginHostsIsCaseInsensitive() {
        XCTAssertEqual(
            CLIParsers.registryLoginHosts(for: "DOCKER.IO"),
            ["registry-1.docker.io", "docker.io", "index.docker.io"]
        )
    }

    func testRegistryLoginHostsPassesThroughOtherRegistries() {
        XCTAssertEqual(CLIParsers.registryLoginHosts(for: "ghcr.io"), ["ghcr.io"])
        XCTAssertEqual(
            CLIParsers.registryLoginHosts(for: "registry.example.com"),
            ["registry.example.com"]
        )
    }

    // MARK: - isRegistryAuthError

    func testIsRegistryAuthErrorMatchesCommonSignals() {
        XCTAssertTrue(CLIParsers.isRegistryAuthError("401 Unauthorized"))
        XCTAssertTrue(CLIParsers.isRegistryAuthError("HTTP/2 401 unauthorized"))
        XCTAssertTrue(CLIParsers.isRegistryAuthError("authentication required"))
        XCTAssertTrue(CLIParsers.isRegistryAuthError("No credentials found for host docker.io"))
        XCTAssertTrue(CLIParsers.isRegistryAuthError("error: insufficient_scope"))
        XCTAssertTrue(CLIParsers.isRegistryAuthError("denied: requested access to the resource is denied"))
    }

    func testIsRegistryAuthErrorRejectsUnrelated() {
        XCTAssertFalse(CLIParsers.isRegistryAuthError(""))
        XCTAssertFalse(CLIParsers.isRegistryAuthError("connection refused"))
        XCTAssertFalse(CLIParsers.isRegistryAuthError("no such image"))
        XCTAssertFalse(CLIParsers.isRegistryAuthError("network timeout"))
    }

    func testIsRegistryAuthErrorIsCaseInsensitive() {
        XCTAssertTrue(CLIParsers.isRegistryAuthError("UNAUTHORIZED"))
        XCTAssertTrue(CLIParsers.isRegistryAuthError("Authentication Required"))
    }

    // MARK: - isLikelyDockerHubImageReferenceError

    func testIsLikelyDockerHubImageReferenceErrorMatches() {
        let msg = "GET https://registry-1.docker.io/v2/library/alpine/manifests/latest: 401 Unauthorized"
        XCTAssertTrue(CLIParsers.isLikelyDockerHubImageReferenceError(msg))
    }

    func testIsLikelyDockerHubImageReferenceErrorRejectsNon401() {
        let msg = "GET https://registry-1.docker.io/v2/library/alpine/manifests/latest: 500 Internal"
        XCTAssertFalse(CLIParsers.isLikelyDockerHubImageReferenceError(msg))
    }

    func testIsLikelyDockerHubImageReferenceErrorRejectsOtherRegistry() {
        let msg = "GET https://ghcr.io/v2/myorg/img/manifests/latest: 401 Unauthorized"
        XCTAssertFalse(CLIParsers.isLikelyDockerHubImageReferenceError(msg))
    }

    // MARK: - looksLikeTopLevelHelp

    func testLooksLikeTopLevelHelpMatches() {
        let output = """
        OVERVIEW: A container platform for macOS

        USAGE: container <subcommand>

        Container subcommands:
          create, start, stop

        Image subcommands:
          pull, push
        """
        XCTAssertTrue(CLIParsers.looksLikeTopLevelHelp(output))
    }

    func testLooksLikeTopLevelHelpRejectsRegularOutput() {
        XCTAssertFalse(CLIParsers.looksLikeTopLevelHelp("docker.io alice\n"))
        XCTAssertFalse(CLIParsers.looksLikeTopLevelHelp(""))
    }
}
