#!/bin/zsh
# Copyright (c) 2026 Design Studio Butterfly Effect
# SPDX-License-Identifier: MIT
# Shared build environment. Never installs tools, SDKs, targets or runtimes.
# Prefer the user's standard Rust setup; reuse the existing dedicated PoC installation if needed.
if [[ -z "${RUSTUP_HOME:-}" && -d "$HOME/.local/share/solidcore-probe/rustup" ]]; then
  export RUSTUP_HOME="$HOME/.local/share/solidcore-probe/rustup"
  export CARGO_HOME="${CARGO_HOME:-$HOME/.local/share/solidcore-probe/cargo}"
fi
if [[ -n "${CARGO_HOME:-}" ]]; then export PATH="$CARGO_HOME/bin:$PATH"; fi
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/.build/rust}"
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"
export SPATIAL_SWIFT_CACHE="${SPATIAL_SWIFT_CACHE:-$ROOT/.build/swift-modules}"
