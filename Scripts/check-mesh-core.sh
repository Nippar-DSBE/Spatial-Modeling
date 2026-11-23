#!/bin/zsh
# Copyright (c) 2026 Design Studio Butterfly Effect
# SPDX-License-Identifier: MIT
set -eu
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_DIR="$(mktemp -d -t spatial-mesh-checks)"
trap 'rm -rf "$CHECK_DIR"' EXIT
xcrun swiftc -module-cache-path "$CHECK_DIR/cache" \
  "$PROJECT_DIR/Spatial Modeling/MeshTopology.swift" \
  "$PROJECT_DIR/Spatial Modeling/MeshDocument.swift" \
  "$PROJECT_DIR/Spatial Modeling/EditHistory.swift" \
  "$PROJECT_DIR/Spatial Modeling/CubePrimitive.swift" \
  "$PROJECT_DIR/Spatial Modeling/MeshGeometry.swift" \
  "$PROJECT_DIR/Tests/MeshCoreChecks.swift" \
  -o "$CHECK_DIR/checks"
"$CHECK_DIR/checks"
