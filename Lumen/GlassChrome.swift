//
//  GlassChrome.swift
//  Lumen
//
//  Thin helpers for applying macOS 26 Liquid Glass to chrome surfaces. The
//  deployment target is macOS 26.5 so `.glassEffect` is available directly; the
//  availability guard exists only as a defensive fallback to a token-tinted
//  `.ultraThinMaterial` should the app ever target an earlier OS.
//

import SwiftUI

extension View {
    /// Applies a Liquid Glass background clipped to `shape` (real glass on
    /// macOS 26+, a material fallback otherwise).
    @ViewBuilder
    func glassChrome(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    /// Applies an interactive Liquid Glass background (for tappable chrome).
    @ViewBuilder
    func interactiveGlassChrome(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
