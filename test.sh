#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

xcrun swiftc -swift-version 6 -parse-as-library \
    -target "$(uname -m)-apple-macosx15.0" \
    -framework AppKit -framework Carbon \
    "$project_dir/Sources/Settings.swift" "$project_dir/Tests/ShortcutTests.swift" \
    -o "$work_dir/ShortcutTests"
"$work_dir/ShortcutTests"
