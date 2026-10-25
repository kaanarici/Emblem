#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
resolved_dir=Emblem.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$resolved_dir"
cp Package.resolved "$resolved_dir/Package.resolved"
