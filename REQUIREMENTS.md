# Courier — Requirements & Implementation Plan

A native macOS API client inspired by [Bruno](https://www.usebruno.com/), built with SwiftUI and SwiftData, following the design language and layout patterns of the Admiral app.

---

## 1. Architecture Overview

### Layout Concept

The window has a **unified sidebar-material background** across the entire window. The content area is an **inset rounded rectangle** ("content card") that floats within this background with padding on all sides (bottom, trailing, and between sidebar). The inspector lives **inside** this content card, not as a separate window-level panel.

A **tab bar** sits above the content card in the window background material. The selected tab connects visually to the content card below it (like Chrome's tabs — the active tab merges into the card surface). The tab bar + content card together form the main working area.

```
┌──────────────────────────────────────────────────────────────────┐
│● ● ● Sidebar  │  ┌─Tab1─┐ Tab2   Tab3                          │
│     toolbar    │  │      └──────────────────────────────────┐    │
│                │  │  ┌────────────────────┬─────────────┐   │    │
│ [WS1]         │  │  │ Method + URL + Send│ Env Selector │   │    │
│ [WS2] ←       │  │  ├────────────────────┴─────────────┤   │    │
│ [WS3]         │  │  │                     │             │   │    │
│                │  │  │  Request Editor     │  Inspector  │   │    │
│ Folders        │  │  │   Params / Headers  │  Response   │   │    │
│  └ Req         │  │  │   Body / Auth       │  Headers    │   │    │
│  └ Req         │  │  │                     │  Body       │   │    │
│ Folders        │  │  │                     │  Timing     │   │    │
│  └ Req         │  │  └─────────────────────┴─────────────┘   │    │
│                │  └──────────────────────────────────────────┘    │
│                │                                     (padding)    │
└────────────────┴─────────────────────────────────────────────────┘
```

### Key Layout Rules

1. **No titlebar** — The window has no native titlebar. `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `styleMask` includes `.fullSizeContentView`. The entire window is edge-to-edge content.
2. **Traffic lights** — The standard window buttons (close/minimize/zoom) overlay the top-left of the sidebar. The sidebar toolbar row reserves space on its leading edge so content doesn't overlap the traffic lights.
3. **Window background** — Sidebar material (`VisualEffectBackground(material: .sidebar)`) fills the entire window, including behind the tab bar and padding areas.
4. **Content card** — A rounded rectangle with its own background material (distinct from sidebar, e.g. `.contentBackground` or a slightly lighter surface). Has `cornerRadius` on all corners. Separated from the window edges by padding (bottom, trailing) and from the sidebar by a gap.
5. **Tab bar** — Lives in the window background area above the content card. The active tab visually connects to the content card (tab bottom edge merges with card top edge, same background). Inactive tabs float in the window background. Chrome-style tab shape. Top-aligned with the sidebar toolbar row.
6. **Inspector inside content card** — The inspector is a right-side panel within the content card, separated from the request editor by a vertical divider. It shares the content card's background. Can be collapsed/expanded.
7. **Sidebar** — Flush to the window's leading edge, edge-to-edge top to bottom. Uses the window's sidebar material naturally.
8. **Two-panel split (not three)** — The NSSplitViewController only manages Sidebar | Content. The content card internally manages its own request editor / inspector split.
9. **Draggable region** — The tab bar area and sidebar toolbar area act as the window drag region (since there's no titlebar to grab).

**Tech Stack:**
- macOS 15+ (Sequoia)
- SwiftUI + AppKit (NSSplitViewController for two-panel layout: Sidebar | Main Area)
- SwiftData for local persistence
- `@Observable` ViewModels + NotificationCenter (matching Admiral patterns)
- URLSession for HTTP execution
- Native Swift `Codable` for import/export

---

## 2. Data Model

### 2.1 Core Entities (SwiftData)

```swift
@Model class Workspace {
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var folders: [Folder]
    @Relationship(deleteRule: .cascade) var environments: [Environment]
    var activeEnvironmentId: UUID?
}

@Model class Folder {
    var id: UUID
    var name: String
    var sortOrder: Int
    var isExpanded: Bool
    var workspace: Workspace?
    var parentFolder: Folder?
    @Relationship(deleteRule: .cascade) var subFolders: [Folder]
    @Relationship(deleteRule: .cascade) var requests: [Request]
}

@Model class Request {
    var id: UUID
    var name: String
    var sortOrder: Int
    var method: String          // GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD
    var urlTemplate: String     // URL with {{variable}} placeholders
    var folder: Folder?
    @Relationship(deleteRule: .cascade) var headers: [Header]
    @Relationship(deleteRule: .cascade) var queryParams: [QueryParam]
    var bodyType: String?       // none, json, xml, formData, urlEncoded, binary, graphql
    var bodyContent: String?
    var authType: String?       // none, bearer, basic, apiKey
    var authData: String?       // JSON-encoded auth config
    var preRequestScript: String?
    var postResponseScript: String?
    var createdAt: Date
    var updatedAt: Date
}

@Model class Header {
    var id: UUID
    var key: String
    var value: String
    var isEnabled: Bool
    var request: Request?
}

@Model class QueryParam {
    var id: UUID
    var key: String
    var value: String
    var isEnabled: Bool
    var request: Request?
}

@Model class Environment {
    var id: UUID
    var name: String
    var workspace: Workspace?
    @Relationship(deleteRule: .cascade) var variables: [EnvironmentVariable]
}

@Model class EnvironmentVariable {
    var id: UUID
    var key: String
    var value: String
    var isSecret: Bool
    var environment: Environment?
}
```

### 2.2 Transient Models (In-Memory)

```swift
struct ResponseResult {
    var statusCode: Int
    var statusText: String
    var headers: [String: String]
    var body: Data
    var bodyString: String?
    var duration: TimeInterval
    var size: Int
}
```

---

## 3. Feature Requirements

### 3.1 Sidebar

| Requirement | Details |
|---|---|
| **Workspace Switcher** | Horizontal ScrollView at the top of the sidebar with `.scrollTargetBehavior(.paging)`. Each "page" is the full width of the sidebar. Shows workspace name + request count. Swipe or click dots to switch. |
| **Collection Tree** | Custom `ForEach` loops (no `List`). Folders are expandable/collapsible with disclosure chevrons. Requests show method badge (colored) + name. |
| **Drag & Drop** | Reorder folders and requests within a workspace. Move requests between folders. String-based drag items matching Admiral pattern. |
| **Context Menus** | Right-click on workspace/folder/request for: New Folder, New Request, Rename, Duplicate, Delete. |
| **Search/Filter** | Text field at top of tree to filter requests by name. |
| **Visual Style** | `VisualEffectBackground(material: .sidebar)`. Opacity-based hover states. SF Symbol icons. Match Admiral's sidebar styling. |

### 3.2 Tab Bar (Window-Level)

| Requirement | Details |
|---|---|
| **Position** | Above the content card, in the window background material area. Each tab represents an open request. |
| **Chrome-style tabs** | Active tab connects to the content card below (shared background, no visible border between them). Inactive tabs float in the window background with a distinct, muted appearance. Curved tab shape with bottom corners that merge into the card. |
| **Tab content** | Method badge (colored) + request name. Close button on hover. |
| **New tab button** | `+` button at the end of the tab strip to create a new unsaved request. |
| **Overflow** | When tabs exceed available width, horizontally scrollable with fade edges. |
| **Drag reorder** | Tabs can be reordered by dragging. |

### 3.3 Content Card

The content card is the inset rounded rectangle that contains both the request editor and the inspector.

| Requirement | Details |
|---|---|
| **Shape** | Rounded rectangle with consistent corner radius (~10–12pt). Top-left corner aligns with the active tab's left edge when possible. |
| **Background** | Distinct from the window/sidebar material — a slightly lighter or opaque surface (e.g. `Color(nsColor: .controlBackgroundColor)` or a custom surface color). |
| **Padding** | Gap between sidebar and card (~12pt). Padding on trailing and bottom edges (~12pt). The tab bar occupies the top, so no top padding — the card connects to the active tab. |
| **Internal layout** | Horizontal split: Request Editor (left) | Inspector (right). Resizable divider between them. Inspector can be collapsed. |

### 3.4 Content Card — Request Editor (Left Side)

| Requirement | Details |
|---|---|
| **URL Bar** | At the top of the request editor area. Method dropdown (GET/POST/PUT/PATCH/DELETE/OPTIONS/HEAD) + URL text field + Send button. URL field parses query params automatically and syncs with Params tab. |
| **Section Tab Bar** | Below the URL bar: **Params**, **Headers**, **Body**, **Auth**, **Variables**, **Scripts**. ForgeTabBar-style with matchedGeometryEffect selection indicator. |
| **Params Tab** | Key-value editor with enable/disable toggles per row. Auto-synced with URL query string. Add/remove rows. |
| **Headers Tab** | Same key-value editor pattern. Common headers autocomplete (Content-Type, Authorization, etc.). |
| **Body Tab** | Body type selector (None, JSON, XML, Form Data, URL Encoded, Binary, GraphQL). JSON/XML: code editor with syntax highlighting. Form Data / URL Encoded: key-value editor. Binary: file picker. GraphQL: query editor + variables editor side by side. |
| **Auth Tab** | Auth type selector (None, Bearer Token, Basic Auth, API Key). Dynamic form based on auth type. Values support `{{variable}}` interpolation. |
| **Variables Tab** | Shows resolved variables from the active environment. Inline preview of what `{{variable}}` resolves to. |
| **Scripts Tab** | Pre-request and post-response script editors. JavaScript-compatible scripting (stretch goal). |

### 3.5 Content Card — Inspector (Right Side)

| Requirement | Details |
|---|---|
| **Background** | Shares the content card background. Separated from the request editor by a thin vertical divider. |
| **Collapse** | Can be collapsed to give the request editor full width. Toggle via button or keyboard shortcut. |
| **Response Header** | Status code (color-coded: green 2xx, yellow 3xx, red 4xx/5xx), duration (ms), response size. |
| **Tab Bar** | Tabs: **Body**, **Headers**, **Cookies**, **Timeline**. |
| **Body Tab** | Auto-formatted based on Content-Type. JSON: collapsible tree view + raw toggle. HTML/XML: syntax highlighted. Images: inline preview. Other: hex/raw view. |
| **Headers Tab** | Response headers as a key-value list. |
| **Cookies Tab** | Parsed Set-Cookie headers in a structured table. |
| **Timeline Tab** | Request lifecycle breakdown: DNS, TCP, TLS, TTFB, download. |
| **Empty State** | "Send a request to see the response" placeholder when no response exists. |

### 3.6 HTTP Client

| Requirement | Details |
|---|---|
| **Engine** | URLSession-based. Configurable timeout, follow redirects toggle, SSL verification toggle. |
| **Variable Interpolation** | Resolve `{{variable}}` placeholders from active environment before sending. |
| **Request History** | Store last N responses per request for quick comparison (stretch). |
| **Cancel** | Ability to cancel in-flight requests. Send button transforms to Cancel while loading. |

### 3.7 Import / Export

| Requirement | Details |
|---|---|
| **Bruno YAML** | Import Bruno collection directories (folder structure + .bru files). |
| **Postman JSON** | Import Postman v2.1 collection exports. |
| **OpenAPI** | Import OpenAPI 3.x specs and generate requests (stretch). |
| **Export** | Export workspace as Bruno-compatible YAML or Postman JSON. |

### 3.8 Environment Management

| Requirement | Details |
|---|---|
| **Environment Selector** | Dropdown in the toolbar or sidebar header to switch active environment. |
| **Environment Editor** | Sheet/panel to create, edit, delete environments and their variables. |
| **Secret Variables** | Variables marked as secret are masked in the UI and excluded from exports. |

### 3.9 Window & App Chrome

| Requirement | Details |
|---|---|
| **No Titlebar** | `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `styleMask` includes `.fullSizeContentView`, `titlebarSeparatorStyle = .none`. Edge-to-edge custom content. |
| **Traffic Lights** | Standard close/minimize/zoom buttons in the top-left of the sidebar. Sidebar toolbar has ~70pt leading padding to avoid overlap. |
| **Drag Region** | Sidebar toolbar area and tab bar area act as window drag regions. |
| **Two-Panel Split** | NSSplitViewController: Sidebar \| Main Area. The main area is a SwiftUI view containing the tab bar + content card. Sidebar is collapsible. |
| **Window Background** | Entire window uses sidebar material. The content card floats within this background. |
| **Frame Persistence** | Window position and size saved between launches via `setFrameAutosaveName`. |
| **Keyboard Shortcuts** | Cmd+Enter to send request. Cmd+N new request. Cmd+T new tab. Cmd+W close tab. Cmd+Shift+N new folder. Cmd+E toggle environments. Cmd+, preferences. |

---

## 4. Implementation Plan

### Phase 1: Foundation (Shell & Data Layer)

**Goal:** App launches with the two-panel layout, content card chrome, and SwiftData models in place.

1. **Window setup** — Replace the template `ContentView` with `MainWindowController` + `MainSplitViewController` (AppKit). No titlebar (`titlebarAppearsTransparent`, `fullSizeContentView`, hidden title, no separator). Traffic lights overlay the sidebar top-left; sidebar toolbar reserves leading space for them. Tab bar and sidebar toolbar areas registered as window drag regions. Two split items: Sidebar | Main Area. Entire window uses sidebar material background.
2. **Content card shell** — The main area is a SwiftUI view with sidebar material background. Inside it, render a rounded rectangle "content card" with padding (trailing ~12pt, bottom ~12pt, leading gap ~12pt from sidebar edge). The card uses a distinct lighter surface background.
3. **Tab bar shell** — Above the content card, in the window background, render an empty tab bar area. Placeholder active tab that connects visually to the card (shared background, no border between active tab bottom and card top).
4. **SwiftData models** — Create all `@Model` classes: `Workspace`, `Folder`, `Request`, `Header`, `QueryParam`, `Environment`, `EnvironmentVariable`. Configure `ModelContainer` with the full schema.
5. **ViewModels** — Create `@Observable` classes: `SidebarViewModel`, `RequestEditorViewModel`, `InspectorViewModel`. Wire up `ModelContext` access.
6. **Styling foundation** — Port/adapt `ForgeStyles` from Admiral: `HoverButtonStyle`, `HoverTextButtonStyle`, color constants, `VisualEffectBackground`. Define content card surface color.
7. **Empty state views** — Sidebar shows "No workspaces" with create button. Content card shows "Select a request". Right side of content card (inspector area) shows "Send a request to see the response".

**Deliverable:** App launches, shows sidebar + floating content card with tab bar, can create/persist a workspace.

---

### Phase 2: Sidebar

**Goal:** Full workspace/folder/request navigation.

1. **Workspace switcher** — Horizontal `ScrollView` with `.scrollTargetBehavior(.paging)` at the top of the sidebar. Each page fills sidebar width. Workspace name, request count, add/settings buttons.
2. **Collection tree** — Custom `ForEach` rendering `Folder` and `Request` rows. Expand/collapse folders. Method badge (colored pill) on request rows. Indent levels for nested folders.
3. **CRUD operations** — Create/rename/delete for workspaces, folders, and requests via context menus and toolbar buttons.
4. **Selection state** — Track selected request ID. Propagate to content area via callback (matching Admiral's pattern). Opening a request creates a tab in the tab bar.
5. **Drag & drop** — Reorder folders and requests. Move requests between folders. Visual drop indicators.

**Deliverable:** Can create workspaces, organize requests into folders, select a request to open as a tab.

---

### Phase 3: Tab Bar & Content Card Layout

**Goal:** Chrome-style tab bar managing open requests, with request editor and inspector inside the content card.

1. **Tab model** — Track open tabs (request IDs), active tab, tab order. ViewModel manages tab state.
2. **Tab bar rendering** — Chrome-style tabs above the content card. Active tab: rounded top corners, bottom edge merges into content card (same background, no border). Inactive tabs: muted appearance in window background. Close button on hover. `+` button for new tab.
3. **Tab interactions** — Click to switch. Drag to reorder. Middle-click or close button to close. Cmd+T new tab, Cmd+W close tab.
4. **Content card internal split** — Horizontal split inside the content card: Request Editor (left) | Inspector (right). Draggable divider. Inspector collapsible.
5. **Tab ↔ content binding** — Switching tabs swaps the request editor and inspector content. Each tab remembers its scroll position and editor state.

**Deliverable:** Can open multiple requests as tabs, switch between them, and see the split editor/inspector layout inside the content card.

---

### Phase 4: Request Editor

**Goal:** Can compose and edit HTTP requests.

1. **URL bar** — At the top of the request editor (inside content card). Method dropdown + URL text field + Send button. Parse URL on change to extract/sync query params.
2. **Section tab bar** — Below URL bar: Params, Headers, Body, Auth. ForgeTabBar-style with matchedGeometryEffect.
3. **Key-value editor component** — Reusable component for Params and Headers tabs. Enable/disable toggle, key/value fields, add/remove buttons.
4. **Body editor** — Body type selector. JSON text editor (basic `TextEditor` initially, syntax highlighting later). Form data key-value editor.
5. **Auth editor** — Auth type picker. Dynamic forms for Bearer, Basic, API Key.

**Deliverable:** Can fully compose a request with URL, params, headers, body, and auth.

---

### Phase 5: HTTP Execution & Response (Inspector)

**Goal:** Can send requests and view responses in the inspector panel.

1. **HTTP service** — `RequestExecutor` class wrapping URLSession. Variable interpolation before sending. Measure timing. Return `ResponseResult`.
2. **Send flow** — Send button triggers execution. Loading state with cancel support. Error handling (timeout, DNS, connection refused, etc.).
3. **Inspector response view** — Inside the content card's right panel. Status badge (color-coded), timing, size. Body tab with JSON pretty-printing and raw toggle. Headers tab. Shares the content card background.
4. **Variable interpolation** — Resolve `{{var}}` from active environment. Show unresolved variables as warnings.

**Deliverable:** End-to-end: compose request, send, view response in the inspector.

---

### Phase 6: Environments

**Goal:** Full environment variable support.

1. **Environment model CRUD** — Create/edit/delete environments per workspace. Variable key-value editor with secret toggle.
2. **Environment selector** — Dropdown in toolbar or sidebar header. Shows active environment name.
3. **Variable resolution** — Pre-send interpolation. Variables tab in request editor shows resolved values. Unresolved variable warnings.

**Deliverable:** Can switch environments and have variables resolve in URLs, headers, and body.

---

### Phase 7: Import

**Goal:** Import existing collections.

1. **Postman JSON importer** — Parse Postman Collection v2.1 format. Map to Workspace > Folders > Requests. Import environments.
2. **Bruno importer** — Parse `.bru` file format and directory structure. Map to data model.
3. **Import UI** — File picker. Preview what will be imported. Conflict resolution (skip/overwrite).

**Deliverable:** Can import Postman and Bruno collections into Courier.

---

### Phase 8: Polish & Advanced Features

1. **Syntax highlighting** — Code editor for JSON/XML/GraphQL bodies with proper highlighting.
2. **Request history** — Store responses per request. Quick comparison view.
3. **Search/filter** — Filter sidebar tree by request name.
4. **Keyboard shortcuts** — Full shortcut support (Cmd+Enter send, Cmd+N new request, etc.).
5. **Cookies tab** — Parse Set-Cookie headers.
6. **Timeline tab** — URLSessionTaskMetrics breakdown.
7. **OpenAPI import** — Parse OpenAPI 3.x specs.
8. **Export** — Export workspace to Postman/Bruno format.

---

## 5. File Structure (Target)

```
Courier/
├── App/
│   ├── CourierApp.swift
│   └── AppDelegate.swift
├── Windows/
│   ├── MainWindowController.swift
│   └── MainSplitViewController.swift
├── Models/
│   ├── Workspace.swift
│   ├── Folder.swift
│   ├── Request.swift
│   ├── Header.swift
│   ├── QueryParam.swift
│   ├── Environment.swift
│   ├── EnvironmentVariable.swift
│   └── ResponseResult.swift
├── ViewModels/
│   ├── SidebarViewModel.swift
│   ├── TabBarViewModel.swift
│   ├── RequestEditorViewModel.swift
│   └── InspectorViewModel.swift
├── Views/
│   ├── Sidebar/
│   │   ├── SidebarView.swift
│   │   ├── WorkspaceSwitcherView.swift
│   │   ├── CollectionTreeView.swift
│   │   ├── FolderRow.swift
│   │   └── RequestRow.swift
│   ├── MainArea/
│   │   ├── MainAreaView.swift          // Window bg + tab bar + content card
│   │   ├── TabBarView.swift            // Chrome-style tabs
│   │   ├── TabItemView.swift           // Individual tab shape/rendering
│   │   └── ContentCardView.swift       // Rounded inset container
│   ├── Content/
│   │   ├── RequestEditorView.swift
│   │   ├── URLBarView.swift
│   │   ├── KeyValueEditor.swift
│   │   ├── BodyEditorView.swift
│   │   └── AuthEditorView.swift
│   ├── Inspector/
│   │   ├── ResponseInspectorView.swift
│   │   ├── ResponseBodyView.swift
│   │   └── ResponseHeadersView.swift
│   └── Shared/
│       ├── CourierStyles.swift
│       ├── CourierTabBar.swift          // Section-level tab bar (Params/Headers/Body/etc)
│       └── MethodBadge.swift
├── Services/
│   ├── RequestExecutor.swift
│   ├── VariableResolver.swift
│   ├── PostmanImporter.swift
│   └── BrunoImporter.swift
├── Extensions/
│   └── ...
├── Shared/
│   └── AppSettings.swift
└── Resources/
    └── Assets.xcassets/
```

---

## 6. Key Design Principles

1. **Follow Admiral patterns** — NSSplitViewController for layout, @Observable ViewModels, NotificationCenter for cross-component communication, ForgeStyles-inspired theming.
2. **Floating content card** — The content area is an inset rounded rectangle over a unified sidebar-material window background. The inspector lives inside the card, not as a separate window panel. This creates visual depth and a clear separation between navigation (sidebar) and workspace (card).
3. **Chrome-style tab bar** — Tabs live in the window background above the content card. The active tab merges into the card surface. This is the primary navigation between open requests.
4. **No List** — Sidebar uses custom `ForEach` with manual styling for full control over appearance and interaction.
5. **SwiftData is the source of truth** — Import files are ingested into SwiftData, not read live. All mutations go through ModelContext.
6. **Offline-first** — Everything works locally. No accounts, no cloud sync, no telemetry.
7. **Keyboard-driven** — Every action reachable via keyboard shortcut.
8. **Progressive disclosure** — Simple requests should be trivial. Advanced features (scripts, auth, variables) available but not in the way.

---

## 7. Implementation Checklist

### Phase 1: Foundation
- [x] Window setup (MainWindowController, no titlebar, fullSizeContentView, traffic light spacing)
- [x] MainSplitViewController (two-panel: Sidebar | Main Area)
- [ ] Window drag regions (sidebar toolbar, tab bar area)
- [x] Sidebar material background across entire window
- [x] Content card shell (rounded rect, padding, lighter surface background)
- [x] Tab bar shell (placeholder area above content card)
- [x] SwiftData schema (Workspace, Folder, Request, Header, QueryParam, Environment, EnvironmentVariable)
- [x] ModelContainer configuration
- [x] SidebarViewModel
- [x] RequestEditorViewModel
- [x] InspectorViewModel
- [x] CourierStyles (HoverButtonStyle, HoverTextButtonStyle, VisualEffectBackground, surface colors)
- [x] Empty state: Sidebar ("No workspaces" + create button)
- [x] Empty state: Content card ("Select a request")
- [x] Empty state: Inspector ("Send a request to see the response")

### Phase 2: Sidebar
- [x] Workspace switcher (horizontal paging ScrollView, snap behavior)
- [x] Workspace page (name, request count, add/settings buttons)
- [x] Collection tree (custom ForEach, no List)
- [x] Folder rows (expand/collapse, chevron, indent levels)
- [x] Request rows (method badge + name)
- [x] Create workspace
- [x] Create folder
- [x] Create request
- [ ] Rename workspace/folder/request
- [x] Delete workspace/folder/request
- [x] Context menus (right-click actions)
- [x] Selection state (track selected request, propagate to content)
- [ ] Drag & drop reorder (folders)
- [ ] Drag & drop reorder (requests)
- [ ] Drag & drop move requests between folders

### Phase 3: Tab Bar & Content Card
- [x] Tab model (open tabs, active tab, tab order in ViewModel)
- [x] Chrome-style tab rendering (active tab merges into content card)
- [x] Inactive tab styling (muted, in window background)
- [x] Tab close button (on hover)
- [ ] New tab button (+)
- [x] Tab click to switch
- [ ] Tab drag to reorder
- [ ] Tab keyboard shortcuts (Cmd+T, Cmd+W)
- [x] Tab overflow (horizontal scroll with fade edges)
- [x] Content card internal split (Request Editor | Inspector)
- [ ] Draggable divider between editor and inspector
- [ ] Inspector collapse/expand toggle
- [x] Tab ↔ content binding (switch tabs swaps content)
- [ ] Per-tab state preservation (scroll position, editor state)

### Phase 4: Request Editor
- [x] URL bar (method dropdown + URL field + Send button)
- [ ] URL parsing (auto-extract query params, sync with Params tab)
- [x] Section tab bar (Params, Headers, Body, Auth, Variables, Scripts)
- [ ] Key-value editor component (reusable, enable/disable toggles, add/remove)
- [ ] Params tab (key-value editor, synced with URL)
- [ ] Headers tab (key-value editor, common headers autocomplete)
- [ ] Body type selector (None, JSON, XML, Form Data, URL Encoded, Binary, GraphQL)
- [ ] Body editor: JSON/XML text editor
- [ ] Body editor: Form Data key-value editor
- [ ] Body editor: URL Encoded key-value editor
- [ ] Body editor: Binary file picker
- [ ] Body editor: GraphQL query + variables
- [ ] Auth type selector (None, Bearer, Basic, API Key)
- [ ] Auth editor: Bearer Token form
- [ ] Auth editor: Basic Auth form
- [ ] Auth editor: API Key form
- [ ] Auth variable interpolation support ({{variable}})

### Phase 5: HTTP Execution & Response
- [ ] RequestExecutor service (URLSession wrapper)
- [ ] Request timing measurement
- [x] ResponseResult model
- [ ] Send button → execute flow
- [ ] Loading state (spinner/progress)
- [ ] Cancel in-flight request (Send → Cancel button)
- [ ] Error handling (timeout, DNS, connection refused, SSL errors)
- [x] Inspector: status badge (color-coded 2xx/3xx/4xx/5xx)
- [x] Inspector: duration display
- [x] Inspector: response size display
- [ ] Inspector: Body tab (JSON pretty-print + raw toggle)
- [ ] Inspector: Body tab (HTML/XML syntax highlighted)
- [ ] Inspector: Body tab (image inline preview)
- [ ] Inspector: Headers tab (response headers list)
- [ ] Variable interpolation before send (resolve {{var}} from active environment)
- [ ] Unresolved variable warnings

### Phase 6: Environments
- [ ] Environment CRUD (create, edit, delete per workspace)
- [ ] Environment variable editor (key-value + secret toggle)
- [ ] Secret variable masking in UI
- [ ] Environment selector (dropdown, shows active environment)
- [ ] Variables tab in request editor (shows resolved values)
- [ ] Pre-send interpolation pipeline

### Phase 7: Import
- [ ] Postman JSON importer (v2.1 collection format)
- [ ] Postman environment import
- [ ] Bruno .bru file parser
- [ ] Bruno directory structure mapping
- [ ] Import UI (file picker)
- [ ] Import preview (show what will be imported)
- [ ] Import conflict resolution (skip/overwrite)

### Phase 8: Polish & Advanced Features
- [ ] Syntax highlighting (JSON/XML/GraphQL code editor)
- [ ] Request history (store last N responses per request)
- [ ] Sidebar search/filter (filter by request name)
- [ ] Keyboard shortcuts (Cmd+Enter, Cmd+N, Cmd+Shift+N, Cmd+E, Cmd+,)
- [ ] Cookies tab (parse Set-Cookie headers)
- [ ] Timeline tab (URLSessionTaskMetrics breakdown)
- [ ] OpenAPI 3.x import
- [ ] Export to Postman JSON
- [ ] Export to Bruno YAML
