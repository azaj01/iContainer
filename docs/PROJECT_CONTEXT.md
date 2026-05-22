# iContainer - Project Context

## Scope
iContainer is a macOS SwiftUI app that manages Apple Container workloads through the `container` CLI.

## Main Components

### Entry point and shell
- `iContainer/iContainerApp.swift`: app entry point, injects shared managers.
- `iContainer/ContentView.swift`: sidebar + detail navigation host, owns the
  create/edit/registry-login sheet state.
- `iContainer/AppNavigation.swift`: navigation state shared across menu bar
  extras and main window.

### Sidebar and welcome screen
- `iContainer/SidebarComponents.swift`: `ServiceStatusView` and
  `ContainerRowView` rows used in the sidebar list.
- `iContainer/WelcomeDashboardView.swift`: home screen shown when nothing
  is selected (metrics + recent containers preview).
- `iContainer/SheetEditors.swift`: shared editors used by the create and
  edit sheets (`MappingPairsEditor`, `EnvironmentVariablesEditor`,
  `MappingRow`, `PathPickerRow`, etc).
- `iContainer/WindowResizeConfigurator.swift`: `NSViewRepresentable` that
  makes sheets resizable with a minimum size.
- `iContainer/ViewExtensions.swift`: `View.applyIf` for conditional
  modifier chains.

### Service layer
- `iContainer/ContainerizationWrapper.swift`: async wrapper around the
  `container` CLI (containers/images/logs/stats/exec/registry). Pure
  parsing is delegated to `CLIParsers`.
- `iContainer/ServiceManager.swift`: polls the container system service,
  tracks status and follows logs. Pure parsing is delegated to
  `CLIParsers`.
- `iContainer/CLIParsers.swift`: single namespace holding every pure
  parser used to read `container` CLI output. Side-effect free and
  exhaustively unit-tested.

### Per-container detail
- `iContainer/ContainerDetailView.swift`: thin TabView host for the
  Info / Stats / Shell / Logs tabs.
- `iContainer/ContainerInfoView.swift`: Info tab, including port links
  and mount links.
- `iContainer/ContainerStatsView.swift`: Stats tab, including chart
  panel and the stats parser.
- `iContainer/ContainerShellView.swift`: Shell tab plus the persistent
  `ContainerShellSession` per container.
- `iContainer/ContainerLogsView.swift`: Logs tab with delta polling.
- `iContainer/ContainerInspectFallback.swift`: untyped-dictionary inspect
  parser for fields that the typed `Decodable` does not cover.
- `iContainer/DetailRowComponents.swift`: `DetailSection`, `DetailRow`,
  `StatusBadge`, `InfoTextStyle`. Shared chrome across the four tabs.

### System service detail
- `iContainer/ServiceDetailView.swift`: system service detail page with
  Info and Logs tabs.

### Tests
- `iContainerTests/CLIParsers*Tests.swift`: ~45 XCTest cases that cover
  the parser surface end-to-end. The test target is declared in the
  pbxproj as a file-system synchronised group, so any new `*.swift`
  file in `iContainerTests/` is picked up automatically.

## Current UX Rules (Important)
- The app shows a dependency error screen if CLI `container` is not available.
- Sidebar container list is sorted:
  - running containers first
  - stopped containers second
  - alphabetical order inside each status group
- `Images` section behavior:
  - section is always visible
  - image rows are shown only when service is running
  - pull-image icon is hidden when service is stopped
- add-container (`+`) toolbar icon is hidden when service is stopped
- Sidebar search field:
  - case-insensitive filter on container name + image reference and on
    image reference
  - shown only when the container service is running (otherwise both
    lists are empty and the field would dangle next to a blank sidebar)
  - the query is cleared automatically when the service stops, so the
    next session starts unfiltered
- `Exec` feature has been removed from UI (replaced by persistent shell workflow).
- Registry auth UX:
  - auth errors (`401`, `unauthorized`, missing credentials) are detected and shown with guided actions
  - `Operation Failed` can show `Login now`, `Copy command`, `Cancel` for registry auth failures
  - `Registry Login` is available from system service context menu
  - registry auth status is shown only in service detail page (not in left sidebar)
  - registry auth panel is rendered after all other service detail sections
- Container settings editing:
  - available from container context menu (`Edit`)
  - opens a guided edit sheet prefilled from inspect data
  - name and image use sidebar/list data as immediate fallback while inspect loads
  - fully qualified inspect hostnames such as `name.test.` are normalized to `name`
  - ports and volumes use the same guided mapping editor pattern
  - mapping editors show configured values in two wrapping columns and do not show a redundant raw mapping field
  - exposed port browser links are shown in the container `Info` tab, not in create/edit forms
  - volume `Host Path` fields include a Finder picker for files or folders
  - create/edit sheets are resizable with a larger centered minimum window
  - save is disabled while edit settings are loading to avoid accidental loss of existing values
  - applying changes recreates the container with updated settings

## Shell Model
- Container shell is persistent per container (session cache by `containerId`).
- Shell starts automatically when opening the Shell tab.
- Commands are sent through a long-lived `container exec ... /bin/sh` process.

## Service Detail Naming
- Service detail header title is:
  - `Apple Container System Service`

## Service Logs
- Apple Container System Service detail uses tabs: `Info` and `Logs`.
- Service logs come from the official `container system logs --last 15m` command and are capped before display.
- Service logs can be followed live with `container system logs --last 15m -f`; disabling follow terminates the child process.
- The Logs tab supports refresh, follow, clear, and copy actions.
- Service logs are global service/runtime diagnostics and are separate from per-container stdout/stderr logs.

## Build/Run Workflow
- Standard build command:
  - `xcodebuild -project iContainer.xcodeproj -scheme iContainer -configuration Debug build`
- During manual relaunch, this sequence is reliable:
  - `pkill -x iContainer || true`
  - `open /Users/nico/Library/Developer/Xcode/DerivedData/iContainer-fpbjeiozuugbpjglzrjgziqvmlne/Build/Products/Debug/iContainer.app`

## Parsing Layer
- All parsing of `container` CLI output lives in `CLIParsers.swift` and
  is `nonisolated`, side-effect free, and unit-testable.
- `ContainerizationWrapper` and `ServiceManager` keep their old static
  parser entry points as thin forwarders to `CLIParsers` so the rest of
  the codebase is unchanged.
- Registry references with a port (e.g. `localhost:5000/myapp`) are
  parsed correctly: the colon in the port is preserved instead of being
  treated as a tag separator.

## Tests
- Unit tests live in `iContainerTests/` and only cover pure types
  (mostly `CLIParsers`). Anything that touches `Process`, `Pipe`, the
  filesystem, or `MainActor`-isolated state belongs in the app target,
  not in tests.
- The test target is already wired in `iContainer.xcodeproj` as a
  file-system synchronised group; new test files in `iContainerTests/`
  are picked up automatically. See `iContainerTests/README.md`.

## Registry Auth Notes
- Current login flow tries Docker Hub aliases:
  - `registry-1.docker.io`
  - `docker.io`
  - `index.docker.io`
- Status parsing guards against false positives:
  - top-level CLI help output must never be treated as authenticated state
