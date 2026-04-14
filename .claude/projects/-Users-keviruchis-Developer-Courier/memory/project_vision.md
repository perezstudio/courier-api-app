---
name: Courier Project Vision
description: Courier is a macOS native API client inspired by Bruno, with Admiral (Mjolnir) design language
type: project
---

Courier is a macOS native API client (like Bruno/Postman) built with SwiftUI + SwiftData.

**Key design decisions:**
- Uses Admiral app (/Users/keviruchis/Developer/Mjolnir) as the design reference for layout, styling, and component patterns
- Admiral uses NSSplitViewController with SwiftUI views hosted inside, @Observable ViewModels, ForgeStyles for theming, and NotificationCenter for cross-component communication
- SwiftData for local persistence — YAML/Postman/etc files are import sources only, not the live storage format
- Sidebar has horizontal-scrolling workspace switcher (snap/paging, no in-between states)
- Sidebar uses custom ForEach loops, NOT SwiftUI List
- Toolbar holds URL field with smart parsing (params, variables)
- Inspector shows query/mutation results with same background as content area (not sidebar material)
- Content area layout mirrors Admiral's split view approach

**Why:** User wants a native macOS alternative to Electron-based API clients, leveraging patterns already proven in Admiral.

**How to apply:** All UI architecture, component patterns, and styling should reference Admiral's implementation. When in doubt, check Mjolnir codebase for precedent.
