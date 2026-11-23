#!/bin/zsh
# Copyright (c) 2026 Design Studio Butterfly Effect
# SPDX-License-Identifier: MIT
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export CAD_TEST_SOURCE="$ROOT/Tests/ObjectTransformChecks.swift"
export CAD_TEST_BINARY=ObjectTransformChecks
exec zsh "$ROOT/Scripts/check-mode-integration.sh"
