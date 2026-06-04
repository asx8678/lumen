//
//  RibbonView.swift
//  Lumen
//
//  Phase 3 (lumen-df8): Obsidian's signature left ribbon — a fixed 44px vertical
//  icon strip pinned to the far left of the window, LEFT of the NavigationSplit
//  sidebar. The surface is a solid `sidebarBackground` (#161616) with a single
//  1px `separator` hairline on its RIGHT edge only. Icons are ~18px, muted
//  `textSecondary`, brightening to `textPrimary` on hover, in ~36px hit targets.
//
//  Item wiring (SF Symbols for now — the Lucide swap is Phase 4):
//    TOP    • Files    → toggle the left sidebar (active when the sidebar shows)
//           • Search   → no-op stub (TODO: quick-switcher not built yet)
//           • Bookmarks→ disabled (TODO: bookmarks feature not built)
//           • Graph    → disabled (LumenGraph is a stub)
//    BOTTOM • Help     → no-op stub (TODO: wire to docs/help)
//           • Settings → opens the app Settings scene
//
//  Settings/help live HERE now (deduped out of the sidebar bottom cluster, which
//  keeps only the "{Vault} ⌄" switcher), matching Obsidian's anatomy.
//

import LumenDesignSystem
import SwiftUI

/// The fixed-width vertical ribbon column. `sidebarVisible` reflects whether the
/// split-view sidebar is currently shown (so the Files item can render an active
/// wash); `toggleSidebar` flips it.
struct RibbonView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.openSettings) private var openSettings

    let sidebarVisible: Bool
    let toggleSidebar: () -> Void

    /// Fixed ribbon width per the Obsidian-look spec.
    static let width: CGFloat = 44

    var body: some View {
        let theme = themeManager.theme
        return VStack(spacing: Spacing.xs) {
            // TOP group.
            RibbonButton(
                systemName: "sidebar.left",
                help: "Toggle sidebar",
                isActive: sidebarVisible,
                action: toggleSidebar
            )
            // TODO: open a quick-switcher / search once one exists.
            RibbonButton(systemName: "magnifyingglass", help: "Search (coming soon)") {}
            // TODO: bookmarks feature not built yet.
            RibbonButton(
                systemName: "bookmark",
                help: "Bookmarks (coming soon)",
                isEnabled: false
            ) {}
            // LumenGraph is a stub; disabled for now.
            RibbonButton(
                systemName: "circle.hexagongrid",
                help: "Graph view (coming soon)",
                isEnabled: false
            ) {}

            Spacer(minLength: 0)

            // BOTTOM group.
            // TODO: wire to docs/help.
            RibbonButton(systemName: "questionmark.circle", help: "Help") {}
            RibbonButton(systemName: "gearshape", help: "Settings") {
                openSettings()
            }
        }
        .padding(.vertical, Spacing.sm)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(theme.color(.sidebarBackground))
        // 1px hairline on the RIGHT edge only.
        .overlay(alignment: .trailing) {
            theme.color(.separator).frame(width: 1)
        }
    }
}

/// A single ribbon icon button: ~18px glyph in a ~36px square hit target, muted
/// by default and brightening on hover, with a neutral active wash when the item
/// represents the current view. Disabled items render faint and ignore clicks.
private struct RibbonButton: View {
    @Environment(ThemeManager.self) private var themeManager
    let systemName: String
    let help: String
    var isActive: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        let theme = themeManager.theme
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18))
                .foregroundStyle(iconColor(theme))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Radius.small)
                        .fill(backgroundWash(theme))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovering = $0 && isEnabled }
        .help(help)
    }

    private func iconColor(_ theme: Theme) -> Color {
        if !isEnabled { return theme.color(.textPlaceholder) }
        if isActive || isHovering { return theme.color(.textPrimary) }
        return theme.color(.textSecondary)
    }

    private func backgroundWash(_ theme: Theme) -> Color {
        if isActive { return theme.color(.activeWash) }
        if isHovering { return theme.color(.hoverWash) }
        return .clear
    }
}
