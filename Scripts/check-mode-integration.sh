#!/bin/zsh
# Copyright (c) 2026 Design Studio Butterfly Effect
# SPDX-License-Identifier: MIT
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/environment.sh"
OUT="${SPATIAL_TEST_ARTIFACTS:-$ROOT/Artifacts/Phase3.2}"
mkdir -p "$OUT"
# Existing toolchain / cached dependencies only; never installs SDKs or Simulator runtimes.
if [[ "${CAD_SKIP_NATIVE_BUILD:-0}" != 1 ]]; then
  cargo +1.99.1 build --locked --offline --manifest-path "$ROOT/Native/SolidCore/Cargo.toml" -p solidcore-probe-bridge
fi
xcrun clang -target arm64-apple-macosx15.0 -c "$ROOT/Spatial Modeling/CAD/CADMemoryMetrics.c" -o "$OUT/CADMemoryMetrics-host.o"
xcrun swiftc -swift-version 6 -target arm64-apple-macosx15.0 -parse-as-library \
  -I "$ROOT/Native/SolidCore/Bridge/include" -L "$CARGO_TARGET_DIR/debug" -lsolidcore_probe \
  -import-objc-header "$ROOT/Spatial Modeling/CAD/CAD-Bridging-Header.h" \
  -module-cache-path "$SPATIAL_SWIFT_CACHE" \
  "$ROOT/Spatial Modeling/MeshTopology.swift" "$ROOT/Spatial Modeling/CubePrimitive.swift" \
  "$ROOT/Spatial Modeling/MeshDocument.swift" "$ROOT/Spatial Modeling/EditHistory.swift" \
  "$ROOT/Spatial Modeling/MeshGeometry.swift" "$ROOT/Spatial Modeling/MeshRenderer.swift" \
  "$ROOT/Spatial Modeling/EditorViewModel.swift" "$ROOT/Spatial Modeling/SelectionController.swift" \
  "$ROOT/Spatial Modeling/CAD/CADMeshConversion.swift" "$ROOT/Spatial Modeling/CAD/CADCommands.swift" "$ROOT/Spatial Modeling/CAD/CADCoordinateConversion.swift" "$ROOT/Spatial Modeling/CAD/CADService.swift" \
  "$ROOT/Spatial Modeling/CAD/CADRenderer.swift" "$ROOT/Spatial Modeling/CAD/CADSession.swift" \
  "$ROOT/Spatial Modeling/ObjectTransform.swift" "$ROOT/Spatial Modeling/WorkspaceModel.swift" "${CAD_TEST_SOURCE:-$ROOT/Tests/ModeIntegrationChecks.swift}" \
  "$OUT/CADMemoryMetrics-host.o" -Xlinker -dead_strip -lc -lm -liconv -o "$OUT/${CAD_TEST_BINARY:-ModeIntegrationChecks}"
"$OUT/${CAD_TEST_BINARY:-ModeIntegrationChecks}"
