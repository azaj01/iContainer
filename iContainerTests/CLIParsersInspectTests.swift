import XCTest
@testable import iContainer

/// Tests for `CLIParsers.parseEditableSettings` and
/// `CLIParsers.normalizedContainerName`.
final class CLIParsersInspectTests: XCTestCase {

    // MARK: - normalizedContainerName

    func testNormalizedContainerNameStripsFullyQualifiedSuffix() {
        XCTAssertEqual(CLIParsers.normalizedContainerName("myapp.test."), "myapp")
    }

    func testNormalizedContainerNameLeavesPlainNames() {
        XCTAssertEqual(CLIParsers.normalizedContainerName("myapp"), "myapp")
        XCTAssertEqual(CLIParsers.normalizedContainerName("my-app-2"), "my-app-2")
    }

    func testNormalizedContainerNameTrimsWhitespace() {
        XCTAssertEqual(CLIParsers.normalizedContainerName("  myapp  "), "myapp")
    }

    func testNormalizedContainerNameHandlesEmpty() {
        XCTAssertEqual(CLIParsers.normalizedContainerName(""), "")
        XCTAssertEqual(CLIParsers.normalizedContainerName("   "), "")
    }

    /// A name like `srv.foo.test.` should become `srv` (first label only).
    func testNormalizedContainerNameKeepsFirstLabel() {
        XCTAssertEqual(CLIParsers.normalizedContainerName("srv.foo.test."), "srv")
    }

    // MARK: - parseEditableSettings

    func testParseEditableSettingsMalformedReturnsNil() {
        XCTAssertNil(CLIParsers.parseEditableSettings(""))
        XCTAssertNil(CLIParsers.parseEditableSettings("not json"))
        XCTAssertNil(CLIParsers.parseEditableSettings("[]")) // empty array, no first element
    }

    func testParseEditableSettingsFromArray() {
        let json = """
        [
          {
            "configuration": {
              "hostname": "myapp.test.",
              "image": { "reference": "docker.io/library/nginx:1.25" },
              "publishedSockets": [
                { "hostPort": 8080, "containerPort": 80 }
              ],
              "mounts": [
                { "source": "/data", "destination": "/var/data" }
              ],
              "initProcess": {
                "environment": ["FOO=bar", "BAR=baz"]
              }
            }
          }
        ]
        """
        let settings = try! XCTUnwrap(CLIParsers.parseEditableSettings(json))
        XCTAssertEqual(settings.image, "docker.io/library/nginx:1.25")
        XCTAssertEqual(settings.name, "myapp") // normalised
        XCTAssertEqual(settings.ports, ["8080:80"])
        XCTAssertEqual(settings.volumes, ["/data:/var/data"])
        XCTAssertEqual(settings.environment, ["FOO=bar", "BAR=baz"])
    }

    func testParseEditableSettingsFromObject() {
        // Some versions of the CLI emit a single object instead of an array.
        let json = """
        {
          "configuration": {
            "hostname": "plain",
            "image": { "reference": "alpine:3.19" }
          }
        }
        """
        let settings = try! XCTUnwrap(CLIParsers.parseEditableSettings(json))
        XCTAssertEqual(settings.image, "alpine:3.19")
        XCTAssertEqual(settings.name, "plain")
        XCTAssertEqual(settings.ports, [])
        XCTAssertEqual(settings.volumes, [])
        XCTAssertEqual(settings.environment, [])
    }

    func testParseEditableSettingsMergesSocketsAndPublishedPorts() {
        // The CLI sometimes exposes ports under publishedSockets, sometimes
        // under publishedPorts. The parser should union both, deduplicated
        // and sorted.
        let json = """
        {
          "configuration": {
            "hostname": "srv",
            "image": { "reference": "img:1" },
            "publishedSockets": [
              { "hostPort": 8080, "containerPort": 80 }
            ],
            "publishedPorts": [
              { "hostPort": 8443, "containerPort": 443 },
              { "hostPort": 8080, "containerPort": 80 }
            ]
          }
        }
        """
        let settings = try! XCTUnwrap(CLIParsers.parseEditableSettings(json))
        XCTAssertEqual(settings.ports, ["8080:80", "8443:443"])
    }

    func testParseEditableSettingsHandlesPortsAsStrings() {
        // The CLI occasionally serialises port numbers as strings.
        let json = """
        {
          "configuration": {
            "image": { "reference": "img:1" },
            "publishedPorts": [
              { "hostPort": "9000", "containerPort": "90" }
            ]
          }
        }
        """
        let settings = try! XCTUnwrap(CLIParsers.parseEditableSettings(json))
        XCTAssertEqual(settings.ports, ["9000:90"])
    }

    func testParseEditableSettingsHandlesMissingFields() {
        let json = """
        { "configuration": {} }
        """
        let settings = try! XCTUnwrap(CLIParsers.parseEditableSettings(json))
        XCTAssertEqual(settings.image, "")
        XCTAssertEqual(settings.name, "")
        XCTAssertEqual(settings.ports, [])
        XCTAssertEqual(settings.volumes, [])
        XCTAssertEqual(settings.environment, [])
    }
}
