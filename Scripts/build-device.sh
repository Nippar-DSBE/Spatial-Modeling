#!/bin/zsh
# Copyright (c) 2026 Design Studio Butterfly Effect
# SPDX-License-Identifier: MIT
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -d "$ROOT/Frameworks/SolidCoreProbe.xcframework" ]]; then
  echo 'Missing device library. Run: zsh Scripts/rebuild-solidcore-device.sh' >&2; exit 1
fi
# Uses the locally generated device XCFramework. No Rust / SDK / Simulator installation.
xcodebuild -project "$ROOT/Spatial Modeling.xcodeproj" -scheme 'Spatial Modeling' \
  -sdk xros -destination 'generic/platform=visionOS' \
  -derivedDataPath "${SPATIAL_DERIVED_DATA:-$ROOT/.build/DerivedData}" \
  -jobs 2 CODE_SIGNING_ALLOWED=NO build
