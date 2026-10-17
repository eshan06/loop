#!/usr/bin/env bash
# Regenerate Loop.xcodeproj from project.yml. Run after adding, moving, or deleting Swift files.
# Homebrew can't build XcodeGen on macOS 13, so this uses the prebuilt release binary.
set -euo pipefail
cd "$(dirname "$0")"

version=2.42.0
bin="${XCODEGEN:-$HOME/.local/xcodegen-$version/xcodegen/bin/xcodegen}"
if ! command -v xcodegen >/dev/null && [[ ! -x "$bin" ]]; then
  echo "Downloading XcodeGen $version..."
  mkdir -p "$(dirname "$(dirname "$(dirname "$bin")")")"
  tmp="$(mktemp -d)"
  curl -sSL -o "$tmp/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip"
  unzip -q -o "$tmp/xcodegen.zip" -d "$(dirname "$(dirname "$(dirname "$bin")")")"
  rm -rf "$tmp"
fi
if command -v xcodegen >/dev/null; then xcodegen generate; else "$bin" generate; fi
