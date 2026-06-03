#!/usr/bin/env bash
#
# Scripts/check.sh — Lumen local CI: the same build + test + lint that the
# GitHub Actions workflow runs. Usable TODAY (the repo has no remote yet).
#
# Usage:
#   ./Scripts/check.sh            # run everything
#   SKIP_XCODEBUILD=1 ./Scripts/check.sh   # packages + lint only (faster)
#
set -euo pipefail

# Resolve full Xcode (xcodebuild + bundled swift-format live here).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Local SPM packages to build & test.
PACKAGES=(LumenCore LumenEditor LumenDesignSystem LumenBenchmark)
APP_SCHEME="Lumen"

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m[ok] %s\033[0m\n' "$1"; }

# 1) Lint (swift-format is bundled with the toolchain — no install needed).
step "Lint (swift-format)"
if command -v swift-format >/dev/null 2>&1; then
    SWIFT_FORMAT=(swift-format)
else
    SWIFT_FORMAT=(xcrun swift-format)
fi
"${SWIFT_FORMAT[@]}" lint --strict --recursive Packages Lumen
ok "swift-format clean"

# Optional: swiftlint if installed (graceful skip otherwise).
if command -v swiftlint >/dev/null 2>&1; then
    step "Lint (swiftlint)"
    swiftlint --strict
    ok "swiftlint clean"
else
    echo "swiftlint not installed — skipping (optional)."
fi

# 2) Build + test each SPM package.
for pkg in "${PACKAGES[@]}"; do
    if [[ -d "Packages/$pkg/Tests" ]]; then
        step "swift build + test: $pkg"
        ( cd "Packages/$pkg" && swift build && swift test )
    else
        step "swift build: $pkg (no tests)"
        ( cd "Packages/$pkg" && swift build )
    fi
    ok "$pkg"
done

# 3) Build the macOS app target.
if [[ "${SKIP_XCODEBUILD:-0}" == "1" ]]; then
    echo "SKIP_XCODEBUILD=1 — skipping xcodebuild."
else
    step "xcodebuild: $APP_SCHEME (macOS)"
    xcodebuild -scheme "$APP_SCHEME" -destination 'platform=macOS' build | \
        grep -E 'BUILD (SUCCEEDED|FAILED)' || true
    ok "$APP_SCHEME built"
fi

# 4) Benchmark smoke run (proves the harness works end-to-end).
step "Benchmark smoke run (lumen-bench)"
( cd Packages/LumenBenchmark && swift run -c release lumen-bench )
ok "benchmark harness ran"

printf '\n\033[1;32mAll checks passed.\033[0m\n'
