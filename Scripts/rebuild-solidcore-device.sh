#!/bin/zsh
# Copyright (c) 2026 Design Studio Butterfly Effect
# SPDX-License-Identifier: MIT
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/Scripts/environment.sh"
FREE_KIB=$(df -k "$ROOT" | awk 'END {print $4}')
echo "Free storage: $((FREE_KIB/1024)) MiB. This script never installs Rust targets, SDKs or Simulator runtimes."
if (( FREE_KIB < 1536000 )); then echo 'Need at least 1500 MiB free.' >&2; exit 1; fi
if ! rustup target list --installed --toolchain 1.99.1 | /usr/bin/grep -qx aarch64-apple-visionos; then
  echo 'Device Rust target missing; stop and check toolchain/storage separately.' >&2; exit 1
fi
export SDKROOT=$(xcrun --sdk xros --show-sdk-path)
export XROS_DEPLOYMENT_TARGET=27.0
cargo +1.99.1 build --locked --offline --release --manifest-path "$ROOT/Native/SolidCore/Cargo.toml" \
  -p solidcore-probe-bridge --target aarch64-apple-visionos
STAGE=$(mktemp -d -t spatial-solidcore-framework)
xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-visionos/release/libsolidcore_probe.a" \
  -headers "$ROOT/Native/SolidCore/Bridge/include" -output "$STAGE/SolidCoreProbe.xcframework"
python3 - "$ROOT" "$STAGE" <<'PY'
from pathlib import Path
import sys,shutil
root,stage=map(Path,sys.argv[1:])
final=root/'Frameworks/SolidCoreProbe.xcframework'; old=stage/'previous.xcframework'
final.parent.mkdir(parents=True,exist_ok=True)
if final.exists():final.rename(old)
try: (stage/'SolidCoreProbe.xcframework').rename(final)
except BaseException:
    if old.exists():old.rename(final)
    raise
shutil.rmtree(stage)
PY
