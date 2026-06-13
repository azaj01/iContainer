import XCTest
@testable import iContainer

/// Tests for `CLIParsers.splitReference` and `CLIParsers.parseImageList`.
final class CLIParsersImageTests: XCTestCase {

    // MARK: - splitReference

    func testSplitReferenceWithTag() {
        let (name, tag) = CLIParsers.splitReference("alpine:3.19")
        XCTAssertEqual(name, "alpine")
        XCTAssertEqual(tag, "3.19")
    }

    func testSplitReferenceFullyQualifiedWithTag() {
        let (name, tag) = CLIParsers.splitReference("docker.io/library/alpine:3.19")
        XCTAssertEqual(name, "docker.io/library/alpine")
        XCTAssertEqual(tag, "3.19")
    }

    func testSplitReferenceWithoutTag() {
        let (name, tag) = CLIParsers.splitReference("alpine")
        XCTAssertEqual(name, "alpine")
        XCTAssertNil(tag)
    }

    func testSplitReferenceEmpty() {
        let (name, tag) = CLIParsers.splitReference("")
        XCTAssertEqual(name, "")
        XCTAssertNil(tag)
    }

    /// A registry port like `localhost:5000` must NOT be mistaken for a tag.
    func testSplitReferencePreservesRegistryPort() {
        let (name, tag) = CLIParsers.splitReference("localhost:5000/myapp")
        XCTAssertEqual(name, "localhost:5000/myapp")
        XCTAssertNil(tag)
    }

    func testSplitReferenceRegistryPortAndTag() {
        let (name, tag) = CLIParsers.splitReference("localhost:5000/myapp:v1.2")
        XCTAssertEqual(name, "localhost:5000/myapp")
        XCTAssertEqual(tag, "v1.2")
    }

    // MARK: - parseImageList

    func testParseImageListEmptyArray() {
        XCTAssertEqual(CLIParsers.parseImageList("[]"), [])
    }

    func testParseImageListMalformedReturnsEmpty() {
        XCTAssertEqual(CLIParsers.parseImageList("not json"), [])
        XCTAssertEqual(CLIParsers.parseImageList(""), [])
        XCTAssertEqual(CLIParsers.parseImageList("{\"not\": \"array\"}"), [])
    }

    func testParseImageListSingleImage() {
        let json = """
        [
          {
            "reference": "docker.io/library/alpine:3.19",
            "fullSize": "7.4 MB",
            "descriptor": {
              "digest": "sha256:abc123",
              "size": 7700000,
              "annotations": {
                "org.opencontainers.image.created": "2024-01-15T10:00:00Z"
              }
            }
          }
        ]
        """
        let images = CLIParsers.parseImageList(json)
        XCTAssertEqual(images.count, 1)
        let image = try! XCTUnwrap(images.first)
        XCTAssertEqual(image.id, "sha256:abc123")
        XCTAssertEqual(image.name, "docker.io/library/alpine")
        XCTAssertEqual(image.tag, "3.19")
        XCTAssertEqual(image.sizeBytes, 7_700_000)
        XCTAssertEqual(image.sizeText, "7.4 MB")
        XCTAssertEqual(image.createdAt, "2024-01-15T10:00:00Z")
    }

    func testParseImageListFallsBackToReferenceAsId() {
        // No digest available → id should default to the reference itself.
        let json = """
        [
          {
            "reference": "myapp:latest"
          }
        ]
        """
        let images = CLIParsers.parseImageList(json)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.id, "myapp:latest")
    }

    func testParseImageListSkipsItemsWithoutIdentity() {
        // No reference and no digest → unidentifiable, must be dropped.
        let json = """
        [
          { "descriptor": {} },
          { "reference": "ok:latest" }
        ]
        """
        let images = CLIParsers.parseImageList(json)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.name, "ok")
    }

    /// container CLI ≥ 1.0 nests reference and descriptor inside a
    /// `configuration` object (`name`, `descriptor`, `creationDate`).
    func testParseImageListModernConfigurationFormat() {
        let json = """
        [
          {
            "configuration": {
              "creationDate": "2026-02-19T01:30:46Z",
              "descriptor": {
                "digest": "sha256:222d1445",
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "size": 511
              },
              "name": "container-registry.oracle.com/os/oraclelinux:9-slim"
            },
            "id": "222d1445",
            "variants": []
          }
        ]
        """
        let images = CLIParsers.parseImageList(json)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.first?.id, "sha256:222d1445")
        XCTAssertEqual(images.first?.name, "container-registry.oracle.com/os/oraclelinux")
        XCTAssertEqual(images.first?.tag, "9-slim")
        XCTAssertEqual(images.first?.sizeBytes, 511)
        XCTAssertEqual(images.first?.createdAt, "2026-02-19T01:30:46Z")
    }
}
