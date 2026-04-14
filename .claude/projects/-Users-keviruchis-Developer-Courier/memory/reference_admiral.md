---
name: Admiral App Reference
description: Admiral (Mjolnir) codebase at /Users/keviruchis/Developer/Mjolnir is the design reference for Courier
type: reference
---

Admiral codebase lives at `/Users/keviruchis/Developer/Mjolnir/Forge/`.

Key reference files:
- **Sidebar**: `Views/Sidebar/SidebarView.swift`, `ViewModels/SidebarViewModel.swift`
- **Content area**: `Views/MainSplitViewController.swift`, `Views/Chat/ChatViewController.swift`
- **Inspector**: `Views/Inspector/InspectorView.swift`, `ViewModels/InspectorViewModel.swift`
- **Toolbar menus**: `Views/Toolbar/ChatMenuController.swift`
- **Styling**: `Shared/ForgeStyles.swift` (HoverButtonStyle, ForgeTabBar, etc.)
- **Models**: `Models/` folder (SwiftData @Model patterns, @Relationship cascades)
- **State management**: @Observable ViewModels + NotificationCenter
- **Window management**: `Windows/MainWindowController.swift` (transparent titlebar, NSSplitViewController)
