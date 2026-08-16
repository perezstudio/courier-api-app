#!/bin/bash
#
# Courier is AppKit-only. See REQUIREMENTS.md §1 and §10.3.
#
# SwiftUI and SwiftData are both banned in the app target: SwiftUI because the
# UI is stock AppKit throughout, SwiftData because persistence is Core Data.
# This runs as a build phase so the rule is enforced by the compiler pipeline
# rather than by review.

set -euo pipefail

SOURCE_DIR="${SRCROOT}/Courier"
status=0

if matches=$(grep -rn --include='*.swift' -E '^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+SwiftUI\b' "$SOURCE_DIR"); then
    while IFS= read -r line; do
        file="${line%%:*}"
        rest="${line#*:}"
        lineno="${rest%%:*}"
        echo "${file}:${lineno}: error: SwiftUI import found — Courier is AppKit-only (REQUIREMENTS.md §1)"
    done <<< "$matches"
    status=1
fi

if matches=$(grep -rn --include='*.swift' -E '^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+SwiftData\b' "$SOURCE_DIR"); then
    while IFS= read -r line; do
        file="${line%%:*}"
        rest="${line#*:}"
        lineno="${rest%%:*}"
        echo "${file}:${lineno}: error: SwiftData import found — Courier persists with Core Data (REQUIREMENTS.md §2)"
    done <<< "$matches"
    status=1
fi

exit $status
