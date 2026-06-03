//
//  Spacing.swift
//  LumenDesignSystem
//
//  Spacing and corner-radius scale tokens, aligned to a 4px base grid to match
//  Obsidian-class chrome density (Phase-1 chrome pass).
//

import CoreGraphics

/// The spacing scale (points), on a 4px base grid: 4 / 8 / 12 / 16 / 20 / 24 / 32.
/// `xxs` (2) is retained for hairline fine-tuning where the grid is too coarse.
public enum Spacing {
    /// Hairline / off-grid fine adjustment (2pt).
    public static let xxs: CGFloat = 2
    /// 4pt — tight inset, marker gaps.
    public static let xs: CGFloat = 4
    /// 8pt — row padding, small stacks.
    public static let sm: CGFloat = 8
    /// 12pt — standard horizontal inset.
    public static let md: CGFloat = 12
    /// 16pt — section gaps.
    public static let lg: CGFloat = 16
    /// 20pt — wide section gaps.
    public static let xl: CGFloat = 20
    /// 24pt — large block separation.
    public static let xxl: CGFloat = 24
    /// 32pt — page-level separation.
    public static let xxxl: CGFloat = 32
}

/// Corner-radius scale tokens (Obsidian-class): small selections/inputs round
/// tightly, buttons/tab-tops a touch more, panels/modals most.
public enum Radius {
    /// 4pt — selection highlights, nav rows, inputs.
    public static let small: CGFloat = 4
    /// 8pt — buttons, tab top corners.
    public static let medium: CGFloat = 8
    /// 12pt — panels, popovers, modals.
    public static let large: CGFloat = 12
}
