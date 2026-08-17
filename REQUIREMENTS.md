# Courier — Requirements & Implementation Plan

A **fully native macOS API client** in the mold of Postman. Pure **AppKit** UI, **entirely local**, persisted with **Core Data**. Built from stock system components throughout: system titlebar, unified toolbar, source-list sidebar, native window tabs, and a split content area with results on the right.

> **Status: clean slate.** This document supersedes all previous plans. No code from the current tree carries forward; the existing sources are deleted in Phase 0.

---

## 1. Product Definition

Courier is a native desktop API client. It should feel like an app Apple shipped — not a web app in a window, not a SwiftUI approximation of one, and not a custom-drawn interface wearing native clothes.

**v1 scope — "core client + environments + import":**

| In scope | Out of scope (post-v1) |
|---|---|
| Workspaces, collections (folder tree), requests | Collection runner / sequenced runs |
| All common body types + auth types | Test assertions, pass/fail reports |
| Environment & collection variables, `{{var}}` resolution | JavaScript pre/post-request scripting (`pm.*` shim) |
| Send / cancel / timing / redirects / cookies | Mock servers, monitors, API documentation |
| Local run history | Any cloud sync, accounts, or collaboration |
| Postman v2.1 + curl + OpenAPI import, Postman export | Team workspaces, comments, sharing |

**Non-negotiables:**

1. **AppKit only.** Zero `import SwiftUI` in the app target. Enforced by a build-phase check (§10.3).
2. **System components first.** If AppKit ships a control for a job, use it. Custom `NSView` subclasses require a written justification (§7.4) — there are exactly three in this plan, and all three are content rendering, not chrome.
3. **Entirely local.** No account, no server, no sync, no telemetry. The network stack is used only for the user's own requests.
4. **Secrets never sit in plaintext on disk.** Secret values live in the Keychain; Core Data stores only a reference.
5. **Core Data is the source of truth.** Imported files are ingested, never read live.

**On portability.** With sync gone, moving collections between machines is a file operation: Postman-format export/import plus a whole-library backup command (§5.4). If cross-machine work becomes a real need later, the natural answer is file-backed collections (a git-friendly directory format) rather than adding a sync service — noted in §12, not built in v1.

---

## 2. Tech Stack

| Layer | Choice |
|---|---|
| Deployment target | macOS 15 (Sequoia) |
| Language | Swift 6, strict concurrency enabled |
| UI | AppKit, 100% programmatic — no Storyboards, no XIBs, no SwiftUI |
| Persistence | Core Data (`NSPersistentContainer`), single local SQLite store |
| Secrets | Keychain Services (`kSecClassGenericPassword`) |
| Networking | `URLSession` + `URLSessionTaskMetrics` |
| Text editing | `NSTextView` on TextKit 2, custom `NSTextStorage` delegate for highlighting |
| Serialization | `Codable` for import/export |
| Tests | Swift Testing (unit), XCUITest (smoke) |

**Deliberately not used:** SwiftUI, SwiftData, CloudKit, Combine (plain callbacks + `NSFetchedResultsController` instead), third-party dependencies of any kind.

**Entitlements:** App Sandbox, `com.apple.security.network.client`, `com.apple.security.files.user-selected.read-write` (import/export, binary bodies), `com.apple.security.files.bookmarks.app-scope` (security-scoped bookmarks for binary body files). No iCloud, no push.

---

## 3. Architecture

### 3.1 Layering

```
┌─────────────────────────────────────────────────────────┐
│  AppKit view controllers  (Windows/, Views/)            │
│    - own no truth; render state, forward intent         │
├─────────────────────────────────────────────────────────┤
│  Controllers / Stores  (Controllers/)                   │
│    - LibraryController (app-wide), WindowController-    │
│      scoped Editor/Response controllers                 │
├─────────────────────────────────────────────────────────┤
│  Services  (Services/)                                  │
│    - RequestExecutor, VariableResolver, SecretStore,    │
│      Importers/Exporters, SyntaxHighlighter             │
├─────────────────────────────────────────────────────────┤
│  Persistence  (Persistence/)                            │
│    - CoreDataStack, Repositories                        │
│    - CDWorkspace / CDFolder / CDRequest / …             │
└─────────────────────────────────────────────────────────┘
```

**Rule:** view controllers never touch `NSManagedObjectContext` directly. They talk to repositories that expose value types (`RequestSnapshot`, `FolderNode`) and accept mutations. This keeps managed objects — which are not `Sendable` — off the UI surface and makes the whole layer testable.

### 3.2 Observation without SwiftUI

There is no `@Observable` / `@State` here. Three mechanisms, used deliberately:

| Need | Mechanism |
|---|---|
| Persisted collections driving lists/trees | `NSFetchedResultsController` → delegate → targeted `NSOutlineView` / `NSTableView` row updates |
| Ephemeral UI state (response pane collapsed, in-flight run) | Plain controller-owned state objects with typed closure callbacks |
| Cross-window events (request renamed, workspace changed, tree reordered) | `NotificationCenter` with typed `Notification.Name` constants and strongly-typed payload wrappers |

Reload **rows, not whole views.** `reloadData()` on every change is the failure mode that makes AppKit apps feel worse than the SwiftUI they replaced.

### 3.3 Concurrency

- `viewContext` is `@MainActor`-confined. Every view controller and repository facing the UI is `@MainActor`.
- Direct user edits write on `viewContext`; bulk work (imports, history pruning, run persistence) goes through `container.performBackgroundTask`.
- **Never pass `NSManagedObject` across an actor boundary.** Pass `NSManagedObjectID` (Sendable) or a value-type snapshot.
- `viewContext.automaticallyMergesChangesFromParent = true`.
- `URLSession` work is fully structured-concurrency based; each in-flight run holds a `Task` handle for cancellation.

---

## 4. Data Model

### 4.1 One store, real relationships

A single local SQLite store in `~/Library/Application Support/Courier/Courier.sqlite`, one model configuration, ordinary Core Data throughout. There are no CloudKit constraints to design around, which means:

- **Non-optional attributes** where the domain says non-optional.
- **Unique constraints** on `id` — the database enforces identity instead of an application-level dedupe pass.
- **Real relationships everywhere**, including run history → request. (Under the earlier CloudKit plan this had to be a bare `UUID` because relationships can't cross store configurations. That constraint is gone; runs are properly related and cascade-delete with their request.)
- **Integer `sortOrder`** with renumber-on-reorder. The fractional-rank scheme in the earlier plan existed to minimize CloudKit write churn; with local-only writes, renumbering a folder's children is bounded and markedly simpler — no float drift, no normalization pass.

Heavy payloads still live in **separate entities** so that listing runs doesn't fault in megabytes of response data. That was always a Core Data faulting concern, not a sync concern, and it still applies.

### 4.2 Entities

```
CDWorkspace
  id: UUID [unique]        name: String
  sortOrder: Int32         iconSymbolName: String = "folder.fill"
  createdAt: Date          activeEnvironmentID: UUID?
  → folders (cascade, inverse: CDFolder.workspace)
  → requests (cascade, inverse: CDRequest.workspace)     // workspace-root requests
  → environments (cascade, inverse: CDEnvironment.workspace)
  → variables (cascade, inverse: CDVariable.workspace)   // collection-scope variables

CDFolder
  id: UUID [unique]        name: String
  sortOrder: Int32         isExpanded: Bool = true
  workspace: CDWorkspace?  parentFolder: CDFolder?
  → subfolders (cascade)   → requests (cascade)

CDRequest
  id: UUID [unique]        name: String
  sortOrder: Int32         method: String = "GET"
  urlTemplate: String = ""
  bodyType: String = "none"        // none|raw|json|xml|text|html|formData|urlEncoded|binary|graphql
  bodyContent: String?
  binaryBookmark: Data?            // security-scoped bookmark for binary bodies
  graphqlVariables: String?
  authType: String = "inherit"     // inherit|none|bearer|basic|apiKey
  authData: Data?                  // JSON blob; secret fields hold Keychain refs
  followRedirects: Bool = true     timeout: Double = 30
  createdAt: Date          updatedAt: Date
  folder: CDFolder?        workspace: CDWorkspace?       // exactly one is non-nil
  → headers (cascade)      → queryParams (cascade)       → runs (cascade)

CDHeader / CDQueryParam
  id: UUID [unique]   key: String   value: String
  isEnabled: Bool = true            sortOrder: Int32
  note: String?                     request: CDRequest?

CDEnvironment
  id: UUID [unique]   name: String   sortOrder: Int32
  workspace: CDWorkspace?            → variables (cascade)

CDVariable
  id: UUID [unique]   key: String
  value: String = ""                 // EMPTY when isSecret — real value is in the Keychain
  isSecret: Bool = false             isEnabled: Bool = true
  sortOrder: Int32
  environment: CDEnvironment?        workspace: CDWorkspace?   // env-scope or collection-scope

CDRun
  id: UUID [unique]        request: CDRequest?           // real relationship
  statusRaw: String = "pending"      // pending|running|completed|failed|cancelled
  isStarred: Bool = false
  statusCode: Int32?       statusText: String?
  duration: Double?        size: Int64?      errorMessage: String?
  requestMethod: String    requestURL: String
  createdAt: Date          timingJSON: String?           // URLSessionTaskMetrics breakdown
  → responseBody (cascade) → responseHeaders (cascade)   → requestSnapshot (cascade)

CDRunResponseBody      data: Binary (allowsExternalBinaryDataStorage) · run: CDRun?
CDRunResponseHeaders   json: String · run: CDRun?
CDRunRequestSnapshot   json: String · run: CDRun?        // resolved URL/headers/body actually sent

CDUIState
  key: String [unique]   json: String                    // per-window open request, split positions
```

### 4.3 History retention

Run history is the only unbounded growth in the store. A retention policy runs at launch on a background context: keep the last *N* runs per request (default 50, configurable) plus every starred run, batch-delete the rest. External binary storage means the response-body files are reclaimed with them.

---

## 5. Store Management

### 5.1 Stack

`NSPersistentContainer` with a single store description. No persistent history tracking, no remote-change notifications, no dedupe pass, no merge-policy tuning — all of that existed to serve CloudKit.

### 5.2 Schema migration

Versioned `.xcdatamodeld` with lightweight migration (`shouldMigrateStoreAutomatically` + `shouldInferMappingModelAutomatically`). The schema is **not** append-only — entities and attributes can be renamed or removed across versions with a mapping model. This meaningfully lowers the cost of getting the model wrong, and is why Phase 1 no longer needs to be perfect before the UI exists.

### 5.3 Failure handling

If the store fails to open, the app does **not** silently delete it (the current tree's behavior, and a data-loss bug). It moves the store aside to `Courier-corrupt-<timestamp>.sqlite`, opens a fresh one, and tells the user where the old file went with a Reveal in Finder button.

### 5.4 Backup & portability

A **Back Up Library…** command writes the full store plus a manifest to a user-chosen location via `NSSavePanel`; **Restore from Backup…** reverses it behind a confirmation. Together with Postman-format export, this is the v1 answer to "how do I get my collections onto my other Mac."

---

## 6. Secrets

Secret environment variables and secret auth fields (bearer tokens, passwords, API keys) never enter Core Data. This matters just as much locally as it did with sync: the store is an unencrypted SQLite file, and API tokens sitting in plaintext in `Application Support` is a bad posture regardless of whether anything syncs.

- Core Data holds `isSecret = true` and an empty `value`. The Keychain item is addressed by a deterministic account string: `variableID.uuidString`, service `"com.perezstudio.Courier.secrets"`.
- `SecretStore` is a thin protocol with a real Keychain implementation and an in-memory one for tests.
- Secrets are masked in the UI (revealed on explicit click), redacted from run request-snapshots, and excluded from every export and backup path.
- Deleting a variable deletes its Keychain item; a launch-time orphan sweep catches any that slipped through.

---

## 7. UI Architecture (AppKit)

### 7.1 Window chrome & layout

Standard macOS document-style window: system titlebar with a unified toolbar, **native window tabs**, a source-list sidebar, and a split content area with the response on the right.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ ● ● ● [◫]   [+] ‖ [GET ▾] [ https://api…/users ] [✈ Send] ‖ [Results|Timeline|History] [◨] │
├──────────────┬───────────────────────────────────┬───────────────────────┤
│ [Workspace ▾]│ ⟨Params│Headers│Body│Auth│Vars⟩   │ 200 OK · 142 ms · 1 KB│
│ [Filter     ]│                                   │ ⟨Body│Headers│Cookies⟩│
│              │                                   │                       │
│ ▾ Users      │       Request settings            │        Results        │
│   · Get User │                                   │                       │
│ ▸ Orders     │                                   │                       │
│              │                                   │                       │
│ [Env ▾]      │                                   │                       │
└──────────────┴───────────────────────────────────┴───────────────────────┘
   sidebar              settings column                  results column
```

1. **System titlebar.** Ordinary `NSWindow`, `.titled` style, `toolbarStyle = .unified`. Traffic lights, title, and full-screen behavior are entirely the system's.
2. **Window title & subtitle.** `window.title` is the active request's name; `window.subtitle` is its collection path. This also supplies the **native tab titles** for free, and is correct in the Window menu and Mission Control.
3. **Source-list sidebar.** `NSSplitViewItem(sidebarWithViewController:)` supplies the material, full-height behavior, and collapse animation. Inside it, `NSOutlineView` with `style = .sourceList` — the system draws the rounded selection, vibrancy, row heights, group headers, and disclosure triangles.
4. **`NSTrackingSeparatorToolbarItem`** bound to the outer split view at index 0, so the toolbar separator tracks the sidebar divider as the user drags it. This is the detail that makes a unified sidebar look right rather than almost right.
5. **Native window tabs** — see §7.2. The tab bar, its `+` button, drag-to-reorder, drag-out-to-new-window, tab overview, and the Window menu's Show Tab Bar / Merge All Windows / Move Tab to New Window are all system-provided.
6. **Content area** stacks vertically: URL bar → inner split view.
7. **One split, three items** — sidebar, settings, results — rather than a split nested inside a content pane, matching how Mail arranges mailboxes, message list, and message. This is what lets both toolbar tracking separators bind to the same split view (dividers 0 and 1).
8. **Column sizing follows Admiral.** The sidebar (200–350pt) and results columns hold their width; the settings column is unbounded and yields. Settings and results share a holding priority so neither snaps back after the other is resized, and both start at `preferredThicknessFraction` 0.4.
9. **Toolbar regions.** Sidebar: toggle at the left edge, new-request at the right. Settings: method picker, URL field, Send. Results: Results/Timeline/History picker, inspector toggle at the right. When the results column collapses, the second tracking separator *and* the mode picker are removed from the toolbar — left in place the separator jumps to the window edge and pushes the toggle into the overflow menu, stranding the user with no way to reopen the pane.
10. **Tinting is the system's.** The method picker and Send use `NSToolbarItem.style = .prominent` with `backgroundTintColor` (the method's colour, and accent/red for send/cancel) — the same construction as Admiral's PR chip. The URL field is a borderless field inside an `NSGlassEffectView`, since a text field has no native toolbar-item equivalent.
11. **Frame persistence** via `setFrameAutosaveName`; per-window open request and split positions via `CDUIState`.

### 7.2 Request tabs are native window tabs

This is the significant change from the previous draft, which specified a hand-rolled tab strip.

macOS already has tabs: `NSWindow.tabbingMode = .preferred` with a shared `tabbingIdentifier` makes every Courier window a tab in one tab group. **One request = one `NSWindow`**, stacked by the system.

What comes free: the tab bar and its visual design, `+` button, drag reorder, drag a tab out into its own window, drag it back, tab overview, Cmd+Shift+[ / ], the full Window menu, and — because tab titles come from `window.title` — correct labels with no extra code.

**Navigation model, matching Finder and Safari:** sidebar selection navigates the *current* tab; Cmd+click a request, or Cmd+T, opens a new tab. Users already know this.

**The consequence to design around:** each tab is a full window, so each has its own sidebar and its own outline view. Tree state that should feel global — expansion, active workspace, scroll position, search filter — is therefore owned by a single app-wide `LibraryController` that all windows observe; only *selection* is per-window. Get this wrong and expanding a folder in one tab won't expand it in the next, which reads as a bug.

This buys back all of Phase 4 from the previous plan, and removes the app's hardest custom-drawing task.

### 7.3 Control mapping

Every region, and the stock AppKit component that implements it:

| Region | Implementation |
|---|---|
| Window | `NSWindow` (titled, unified toolbar, `tabbingMode = .preferred`) |
| Request tabs | **System window tabs** — no custom view |
| Toolbar | `NSToolbar` + delegate; `NSTrackingSeparatorToolbarItem`, `NSSearchToolbarItem`, `.toggleSidebar`, autosaved configuration |
| Root split | `NSSplitViewController`, item 0 via `sidebarWithViewController:` |
| Workspace switcher | `NSPopUpButton` at the sidebar head |
| Collection tree | `NSOutlineView`, `style = .sourceList`, standard `NSTableCellView` (`imageView` + `textField`), group rows for sections, system disclosure triangles, `NSOutlineViewDataSource` drag/drop |
| Method badge in tree rows | `NSTableCellView` with a second `NSTextField` styled per method — content, not chrome |
| Content/response split | Nested `NSSplitViewController`, response item collapsible, `autosaveName` set |
| Method picker | `NSPopUpButton` with per-item attributed titles |
| URL bar | Borderless `NSTextField` in an `NSGlassEffectView`; `{{variable}}` highlighting on the field editor while editing and on the attributed value when not |
| Send / Cancel | `NSToolbarItem`, prominent style; image and tint swapped by state. Cmd+Return lives in the File menu, since a toolbar item has no key equivalent |
| Request sections (Params/Headers/Body/Auth/Vars) | `NSTabViewController`, `tabStyle = .segmentedControlOnTop`, wrapped in a safe-area container (see below) |
| Results mode (Results/Timeline/History) | `NSSegmentedControl` in the toolbar, driving a plain swapping controller — a tab controller would draw a second row of tabs under the control driving it |
| Results sections (Body/Headers/Cookies) | `NSSegmentedControl` inside the Results view |
| Method picker | `NSMenuToolbarItem`, prominent style, tinted per verb |
| Body view mode (pretty/raw/preview) | `NSSegmentedControl` |
| Key-value editors | `NSTableView` (view-based) — checkbox, key, value, note, delete columns; inline `NSTextField` editing; tab-to-next-field |
| Body editor | `NSTextView` (TextKit 2) + `NSRulerView` line numbers + `NSTextStorageDelegate` highlighting |
| Response body | `NSTextView` (read-only), `NSOutlineView` (JSON tree), `NSImageView` (images) |
| Response headers / cookies | `NSTableView` (view-based) |
| Run history | `NSTableView` (view-based) |
| Loading / progress | `NSProgressIndicator` |
| Status badge | `NSTextField` with a system-colored background layer |
| Environment editor | Sheet-presented `NSWindowController` containing an `NSSplitViewController` |
| Settings | `NSTabViewController` with `tabStyle = .toolbar` — the stock Settings-window layout |
| Menus & shortcuts | `NSMenu` in code; actions via the responder chain with `validateMenuItem(_:)` |
| Dialogs | `NSAlert`, `NSOpenPanel`, `NSSavePanel` |

### 7.4 The three custom views, justified

Per §1.2, every custom `NSView` needs a reason. There are three, and all render content rather than chrome:

1. **`TimelineChartView`** — a bar chart of `URLSessionTaskMetrics` phases. AppKit ships no chart control.
2. **`HexDumpView`** — fallback rendering for binary response bodies. No system equivalent.
3. **`EmptyStateView`** — centered symbol + label + optional button. macOS has no empty-state control; this is a thin `NSStackView` composition rather than custom drawing.

Everything else in §7.3 is a stock control. If a fourth candidate appears during implementation, it needs the same justification or it doesn't get built.

### 7.5 Native wins to actually claim

Going AppKit costs code; these are the things that make it pay:

- **Window tabs, entirely free** — including drag-out, merge, overview, and the Window menu (§7.2).
- **Undo/redo** — `viewContext.undoManager` handed to the window. **Not as free as this section originally claimed:** Core Data groups undo registrations by event loop iteration, and repositories save on every mutation without closing a group, so one Cmd+Z reverts a whole batch. Verified in Phase 3 — a single delete followed by Cmd+Z took the tree from six rows to three. Correct undo needs explicit `begin`/`endUndoGrouping` around each repository mutation, and reverting only changes objects in memory so the undo notification must re-save and reload. Left unwired (Cmd+Z inert) until that work is scheduled.
- **Accessibility mostly for free** — stock controls ship with correct VoiceOver roles and full keyboard access. The three custom views in §7.4 need explicit `NSAccessibility` work; nothing else should.
- **Appearance for free** — source list, tab bar, toolbar, and segmented controls all handle Dark Mode, Increase Contrast, and accent color changes without app code.
- **Services menu, Sharing, Quick Look** on response bodies.
- **Real drag & drop** — drag a request to Finder to export it, drop a `.json` collection on the sidebar to import it.
- **State restoration** — reopen with the exact windows, tabs, splits, and selection.
- **Toolbar customization** — users rearrange their own toolbar; free from `NSToolbar`.

---

## 8. Feature Requirements

### 8.1 Sidebar
Workspace popup at the head · source-list outline tree with system disclosure and colored method badges · workspace-root requests as well as foldered ones · create/rename/duplicate/delete for workspace, folder, request · inline rename via the standard cell text field · context menus · multi-select delete · drag-and-drop reorder and reparent with system drop indicators · live filter driven by `NSSearchToolbarItem` · shared expansion/workspace state across all tabs (§7.2).

### 8.2 Tabs & windows
One request per window tab · titles and subtitles from `window.title` / `window.subtitle` · sidebar selection navigates the current tab; Cmd+click or Cmd+T opens a new one · Cmd+W closes the tab · dirty state reflected in the title · everything else — reorder, drag-out, merge, overview, Cmd+Shift+[ / ] — inherited from the system.

### 8.3 Request editor
**URL bar:** lives in the toolbar over the settings column — method picker, URL field, Send. Editing the URL syncs the Params table bidirectionally.
**Params / Headers:** key-value tables, per-row enable, note column, common-header autocomplete, bulk-edit text mode.
**Body:** none · raw (JSON/XML/HTML/Text/JS) · form-data (with file rows) · x-www-form-urlencoded · binary (file picker + security-scoped bookmark) · GraphQL (query + variables panes). Syntax highlighting, format/prettify action, size indicator.
**Auth:** inherit · none · bearer · basic · API key (header or query). Secret fields route to the Keychain. All values support `{{var}}` interpolation.
**Variables:** resolved-value table showing scope precedence and unresolved warnings.

### 8.4 Response pane (right side of the content split)
Status badge (colored by class) · duration · size · Body / Headers / Cookies / Timeline tabs · body auto-formatted by Content-Type with a pretty/raw/preview segmented control and a collapsible JSON tree · image preview · search-in-body · copy/save response · cookie table parsed from `Set-Cookie` · timeline from `URLSessionTaskMetrics` (DNS/TCP/TLS/TTFB/download) · run history list with starring and diff-against-previous · empty and error states · collapsible to give the editor full width.

### 8.5 HTTP engine
`URLSession` with per-request timeout and redirect policy · full variable interpolation before send · cancellation · cookie jar via `HTTPCookieStorage` · gzip/deflate · streaming download for large bodies with a size cap before rendering · TLS trust decisions surfaced (never silently bypassed) · every run persisted with a redacted request snapshot.

### 8.6 Variables & environments
Scopes, in resolution order: **request → environment → collection → global**. Environment CRUD in a sheet; per-workspace active environment selected from the toolbar popup; secret masking; unresolved-variable warnings inline in the URL bar and in the Variables tab.

### 8.7 Import / export
Postman Collection v2.1 import (folders, requests, auth, bodies, variables) · Postman environment import · curl-command paste-to-request · OpenAPI 3.x import · Postman v2.1 export · import preview with conflict resolution (skip / overwrite / duplicate) · library backup and restore (§5.4) · secrets never written to exports or backups.

### 8.8 Shortcuts
Cmd+Enter send · Cmd+. cancel · Cmd+N request · Cmd+Shift+N folder · Cmd+T new tab · Cmd+W close tab · Cmd+Shift+[ / ] switch tabs (system) · Cmd+E environments · Cmd+F filter sidebar · Cmd+Opt+F find in response · Cmd+Ctrl+S toggle sidebar · Cmd+Opt+I toggle response pane · Cmd+, settings · Cmd+Z / Shift+Cmd+Z undo/redo.

---

## 9. Implementation Plan

Each phase ends with a runnable, demoable app. No phase leaves the build broken.

### Progress

| Phase | Status | Commit |
|---|---|---|
| 0 — Clear the slate | **Done** | `3297a81` |
| 1 — Persistence foundation | **Done** | `eef354e` |
| 2 — App shell & window tabs | **Done** | `9547409` |
| 3 — Sidebar | **Done** | `37b9f2a` |
| 4 — Request editor | **Done** | `aa0e58a` |
| 5 — HTTP engine & response pane | **Done** | `e057ca2` |
| 6 — Environments & variables | **Done** | `d101ca7` |
| 7 — Import/export, accessibility & polish | Not started | — |

**130 tests passing.** The app composes, sends, cancels, and inspects real
requests, with environments driving variable resolution.

### Carried forward — built but incomplete

Things a phase delivered in part, deliberately, and where the rest belongs:

| Item | State | Lands in |
|---|---|---|
| **Undo/redo** | Unwired; Cmd+Z is inert. Reasoning in §7.5, tracked as open question 1. | Its own pass |
| **Binary request bodies** | Body type selectable; no file picker, so nothing is sent. | Phase 7 |
| **`multipart/form-data`** | Encoded as a query string, so file parts are unsupported. Fine for plain fields. | Phase 7 |
| **GraphQL** | Body type exists and posts the query; no separate variables pane (§8.3). | Phase 7 |
| **Auth `inherit`** | Sends nothing. Folder- and collection-level auth is not modeled. | Post-v1 |
| **Response diff** | History lists and replays runs; no diff-against-previous (§8.4). | Phase 7 |
| **Tab dirty indicator** | Not built. With a 400ms autosave debounce nothing stays dirty, so the indicator in §8.2 would always be off. | Dropped, deliberately |
| **JSON tree view** | Body renders pretty/raw with highlighting; no collapsible outline (§8.4). | Phase 7 |
| **Settings window** | Menu item present but disabled. | Phase 7 |
| **History retention tuning** | Prune walks every request's runs at launch — correct, but O(all runs). | Phase 7 profiling |

### Verification debt

Covered by tests but never confirmed on screen, because AppKit does not expose
these to accessibility scripting:

- Sidebar drag-and-drop gesture, and the sidebar context menu (Phase 3).
- The environment editor's windowed presentation, after it was converted from a
  sheet (Phase 6).

Worth a human passing over these before v1.

### Phase 0 — Clear the slate
Delete `Courier/`, `CourierTests/`, `CourierUITests/` sources. Rebuild the Xcode target from empty: `main.swift` + `AppDelegate`, no Storyboard, no SwiftUI. Configure Swift 6 strict concurrency, App Sandbox, network-client and file-access entitlements. Add the `import SwiftUI` build-phase guard (§10.3). Create the versioned `.xcdatamodeld`.
**Deliverable:** empty window launches and is sandboxed correctly.

### Phase 1 — Persistence foundation
Full Core Data model per §4. `CoreDataStack` with lightweight migration, corrupt-store quarantine (§5.3), and history retention (§4.3). `SecretStore` (Keychain + in-memory test double). Repository layer with value-type snapshots. Reorder/reparent helpers. Unit tests against an in-memory store covering CRUD, ordering, cascade deletes, retention pruning, and Keychain round-trips.
**Deliverable:** no UI, but `swift test` proves the whole data layer.

### Phase 2 — App shell & window tabs
`MainWindowController` with system titlebar, unified toolbar, and `tabbingMode = .preferred` · `NSToolbar` delegate (sidebar toggle, tracking separator, search, environment popup, new-request, settings) · outer `NSSplitViewController` with a sidebar item · content container stacking URL bar and inner split · inner `NSSplitViewController` with autosaved positions · `NSTabViewController` shells for both section bars · `LibraryController` as the shared cross-window state owner · window controller registry, tab open/close/navigate plumbing · full `NSMenu` tree with validated actions · title/subtitle binding · empty states · state restoration scaffolding.
**Deliverable:** the app's chrome is complete and correct, tabs work end to end, and regions are empty placeholders.

### Phase 3 — Sidebar
Workspace popup · source-list `NSOutlineView` backed by repositories + FRC · method badges · CRUD, inline rename, duplicate, delete · context menus · drag & drop reorder/reparent · search filter · shared expansion state verified across tabs · undo/redo wired.
**Deliverable:** full navigation and organization; selection navigates the current tab, Cmd+click opens a new one.

### Phase 4 — Request editor
URL bar with variable highlighting · method picker · request-section tab view controller · key-value `NSTableView` component (reused by Params, Headers, form-data, URL-encoded, variables) · URL ↔ params sync · body editors with TextKit 2 highlighting, line numbers, prettify · auth forms with Keychain-backed secret fields · dirty tracking and autosave.
**Deliverable:** any request can be fully composed and persisted.

### Phase 5 — HTTP engine & response pane
`RequestExecutor` with cancellation, metrics, redirects, cookies · `VariableResolver` with the four-scope precedence chain · run persistence · response header bar (status/duration/size) · body rendering (pretty/raw/JSON tree/image/hex) · headers, cookies, timeline tabs · find-in-response · run history list with starring · error states · pane collapse.
**Deliverable:** end-to-end — compose, send, cancel, inspect, and revisit history.

### Phase 6 — Environments & variables
Environment editor sheet · variable tables with secret toggles · secret masking and reveal · Keychain integration and orphan sweep · toolbar environment popup · Variables tab showing resolved values and precedence · unresolved-variable warnings.
**Deliverable:** environments fully drive request resolution.

### Phase 7 — Import/export, accessibility & polish
Postman v2.1 importer/exporter · Postman environment import · curl paste · OpenAPI 3.x · import preview and conflict resolution · drag-and-drop file import · library backup/restore · settings window · `NSAccessibility` work on the three custom views (§7.4) · Dark/Light and Increase Contrast verification · Reduce Motion · performance profiling (10k-request collection, 50MB response, 20 open tabs) · Services/Sharing/Quick Look integration.
**Deliverable:** shippable v1.

*Two phases lighter than the previous draft: CloudKit hardening is gone, and the custom tab bar phase is absorbed by the system.*

---

## 10. Project Structure & Conventions

### 10.1 Target layout

```
Courier/
├── App/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── MainMenu.swift
│   └── WindowRegistry.swift        // tab group + window lifecycle
├── Windows/
│   ├── MainWindowController.swift
│   ├── MainToolbarDelegate.swift
│   ├── RootSplitViewController.swift
│   ├── ContentViewController.swift            // URL bar + inner split
│   └── EditorResponseSplitViewController.swift
├── Persistence/
│   ├── Courier.xcdatamodeld
│   ├── CoreDataStack.swift
│   ├── HistoryRetention.swift
│   ├── Model/            // CD* NSManagedObject subclasses
│   └── Repositories/     // WorkspaceRepository, RequestRepository, RunRepository, …
├── Controllers/
│   ├── LibraryController.swift     // app-wide shared tree/workspace/filter state
│   ├── SidebarController.swift
│   ├── EditorController.swift
│   └── ResponseController.swift
├── Views/
│   ├── Sidebar/          // WorkspacePopUpController, CollectionOutlineViewController, cells
│   ├── Editor/           // URLBarViewController, RequestSectionsTabViewController,
│   │                     // KeyValueTableViewController, BodyEditorViewController,
│   │                     // AuthEditorViewController
│   ├── Response/         // ResponseSectionsTabViewController, body renderers,
│   │                     // TimelineChartView, HexDumpView, RunHistoryViewController
│   ├── Environments/     // EnvironmentWindowController
│   ├── Settings/         // SettingsTabViewController
│   └── Shared/           // CodeTextView, EmptyStateView, MethodStyle
├── Services/
│   ├── RequestExecutor.swift
│   ├── VariableResolver.swift
│   ├── SecretStore.swift
│   ├── SyntaxHighlighter.swift
│   ├── Backup.swift
│   ├── Import/           // PostmanImporter, OpenAPIImporter, CurlParser
│   └── Export/           // PostmanExporter
├── Support/
│   ├── Theme.swift       // method colors + metrics only
│   ├── Notifications.swift
│   └── Extensions/
└── Resources/
```

### 10.2 Conventions
- Programmatic Auto Layout only; no XIBs, no Storyboards, no frame math outside the three custom views.
- One view controller per region; view controllers under ~400 lines — split when they exceed it.
- **Semantic system colors everywhere** — `.labelColor`, `.secondaryLabelColor`, `.separatorColor`, `.controlAccentColor`, `.selectedContentBackgroundColor`. `Theme` carries only method colors and layout metrics; it is deliberately thin, because stock controls already handle appearance.
- Repositories return value types; managed objects never leave `Persistence/`.
- New custom `NSView` subclasses require a justification added to §7.4.

### 10.3 The AppKit guard
A "Run Script" build phase fails the build on any SwiftUI import in the app target:

```bash
if grep -rn --include=\*.swift -E '^\s*import\s+SwiftUI' "$SRCROOT/Courier"; then
  echo "error: SwiftUI import found — Courier is AppKit-only"; exit 1
fi
```

---

## 11. Risks

| Risk | Mitigation |
|---|---|
| **Window-tab state sharing.** One window per tab means N sidebars, N outline views, N fetched-results controllers. Expansion or workspace state diverging between tabs reads as a bug. | `LibraryController` is the single owner of shared tree state; windows observe it and hold only selection. Built in Phase 2 and verified before the sidebar lands in Phase 3. |
| Memory with many open tabs. | Repositories hand out value snapshots, and `LibraryController` caches one tree snapshot shared by all windows. Profile at 20 tabs in Phase 7. |
| `NSOutlineView` + Core Data + drag-reorder + FRC is still the most bug-prone combination in the app. | Repository returns an immutable tree snapshot; the outline view diffs against it. Cover reorder/reparent with unit tests before wiring the UI. |
| Store corruption or a failed migration destroys the library, and there's no cloud copy to fall back on. | Quarantine rather than delete (§5.3); back up before every migration attempt; ship backup/restore in Phase 7. **This risk is materially higher without sync.** |
| Large responses (50MB+) rendered in `NSTextView`. | Size cap before rendering with an explicit "show anyway" affordance; bodies stored as external binary data. |
| Run history grows unbounded. | Retention policy at launch (§4.3), configurable in settings. |
| Sandbox + user-supplied URLs + client certificates. | `network.client` covers ordinary requests. Client certs and custom CAs are post-v1; don't design around them now. |

---

## 12. Settled & Open

**Settled:**
- **Bundle identifier:** `com.perezstudio.Courier`. Keychain service: `com.perezstudio.Courier.secrets`. App group / support directory: `~/Library/Application Support/Courier/`.

**Open — none of these block Phase 0:**
1. **Undo/redo scheduling** — deferred out of Phase 3 for the reason in §7.5. Wire it as its own pass (explicit undo grouping per repository mutation, plus re-save and reload on the undo notification), or drop Cmd+Z from v1?
2. **Distribution** — Developer ID direct download, or Mac App Store? Affects sandbox strictness and the update mechanism.
3. **Bruno import** — an earlier plan included it. Still wanted, or are Postman + OpenAPI + curl enough for v1?
4. **File-backed collections** — the long-term portability answer if you ever want collections in git or shared across machines. Worth designing the export format with that future in mind, or not a concern?
5. **App icon** — the existing `AppIcon.icon` asset is the one thing worth salvaging from the current tree if you want it.
