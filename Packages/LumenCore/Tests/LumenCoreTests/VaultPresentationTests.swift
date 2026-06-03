//
//  VaultPresentationTests.swift
//  LumenCoreTests
//
//  P1.2: unit tests for the pure presentation/command-enablement helpers used
//  by the app target's window title and menu wiring.
//

import Foundation
import XCTest

@testable import LumenCore

final class VaultPresentationTests: XCTestCase {
    func testWindowTitleWithVault() {
        let vault = Vault(root: URL(fileURLWithPath: "/tmp/Notes"))
        XCTAssertEqual(VaultPresentation.windowTitle(for: vault), "Lumen — Notes")
    }

    func testWindowTitleNoVault() {
        XCTAssertEqual(VaultPresentation.windowTitle(for: nil), "Lumen — No Vault")
    }

    func testCanActOnVault() {
        XCTAssertFalse(VaultPresentation.canActOnVault(nil))
        XCTAssertTrue(
            VaultPresentation.canActOnVault(Vault(root: URL(fileURLWithPath: "/tmp/V"))))
    }
}
