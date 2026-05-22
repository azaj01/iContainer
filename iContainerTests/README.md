# iContainerTests

Unit tests for the pure parsers in `CLIParsers.swift`. All tests run without
spawning a process, touching the network, or hitting the filesystem.

## Files

| File | Covers |
|------|--------|
| `CLIParsersImageTests.swift` | `splitReference`, `parseImageList` |
| `CLIParsersRegistryTests.swift` | `parseRegistryHosts`, `registryLoginHosts`, `isRegistryAuthError`, `isLikelyDockerHubImageReferenceError`, `looksLikeTopLevelHelp` |
| `CLIParsersInspectTests.swift` | `parseEditableSettings`, `normalizedContainerName` |
| `CLIParsersServiceTests.swift` | `parseServiceDetails`, `limitedLogOutput` |

About **45 test cases** in total.

## One-time setup (~30 seconds)

The `iContainer.xcodeproj` does not yet declare a unit test target — the
`pbxproj` for Xcode 26 (`objectVersion = 77`) is sensitive to manual edits,
so the target is best created from the Xcode UI:

1. Open `iContainer.xcodeproj` in Xcode.
2. **File → New → Target…** (or `⌘⇧T` on the project navigator).
3. Choose **macOS → Unit Testing Bundle** and click Next.
4. Set **Product Name**: `iContainerTests`.
5. Set **Target to be Tested**: `iContainer`.
6. **Language**: Swift. **Project**: iContainer. Click Finish.
7. Xcode will auto-create an `iContainerTests/` folder with a sample test —
   delete the auto-generated `iContainerTests.swift` file (the real tests
   are already in this folder and will be picked up by the file-system
   synchronised group).
8. In the test target's **Build Settings**, make sure
   **Default Actor Isolation** is set to `MainActor` (matches the app
   target — already the project default).

## Running the tests

- `⌘U` in Xcode, or
- From CLI:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild test \
    -project iContainer.xcodeproj \
    -scheme iContainer \
    -destination 'platform=macOS'
  ```

## Adding new tests

Drop a new `*.swift` file in this folder. Because the target is configured
as a file-system synchronised root group, Xcode picks it up automatically —
no `pbxproj` edits required.

All test files should:
- `@testable import iContainer`
- subclass `XCTestCase`
- exercise only `CLIParsers` (or other pure types). Anything that touches
  `Process`, `Pipe`, the network, or `MainActor`-isolated state belongs in
  the app target, not here.
