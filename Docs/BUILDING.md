# Reproducible native build

The pinned source snapshot is in `Native/SolidCore/Vendor/SolidCore`. `UPSTREAM.json` records commit provenance; `Cargo.lock` pins all 35 packages: the bridge, the DSBE conversion crate and 33 third-party packages. `Scripts/rebuild-solidcore-device.sh` runs Rust 1.99.1 for `aarch64-apple-visionos`, uses the selected Xcode xros SDK and builds the five CAD library crates, the local MIT conversion adapter, and their locked dependencies. No SolidCraft UI, renderer, MCP, plugin framework, external process or runtime service is included.

Run the explicit first-time toolchain/target setup and `cargo fetch --locked` in README, then run the device rebuild script. It creates `Frameworks/SolidCoreProbe.xcframework` with one arm64/xros static-library slice. It does not download/install toolchains, targets, SDKs or Simulator runtimes. The script stops on a missing target or insufficient disk space. Do not add a Simulator slice without separately evaluating storage and support.

`Scripts/environment.sh` uses standard Cargo/Rustup settings, or the existing user-local dedicated PoC installation if present. Override `CARGO_HOME`, `RUSTUP_HOME`, `CARGO_TARGET_DIR`, `SPATIAL_SWIFT_CACHE`, `SPATIAL_DERIVED_DATA`, `SPATIAL_TEST_ARTIFACTS` as needed. The default cache root is `.build/` and local evidence is in ignored `Artifacts/`.

For a clean cached-source verification, set `CARGO_TARGET_DIR` to an empty temporary directory, run `cargo +1.99.1 check --locked --offline --manifest-path Native/SolidCore/Cargo.toml -p solidcore-probe-bridge --lib`, then run the native library build. A full link generates large temporary outputs; avoid redundant caches on a small disk.

The binary is reproducible by source/version/target and tested behavior. Bit-for-bit identical archives across machines are not promised: archive/toolchain metadata may differ. The repository candidate deliberately excludes prebuilt archives, which can contain build-machine paths and exceed GitHub's normal file size limit.

Signing uses optional `Config/Signing.local.xcconfig`:

```text
SPATIAL_DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

This local file is ignored. The source-candidate exporter replaces any working-project Team identifier with `$(SPATIAL_DEVELOPMENT_TEAM)` in the exported project; the working signing setup is preserved. Configure your own unique bundle identifier in Xcode for deployment. `build-device.sh` uses CODE_SIGNING_ALLOWED=NO and only verifies compilation/linking.

The public source package omits upstream fixture data and images. Library source files remain intact; the workspace manifest carries a prominent packaging-change notice. App tests build the bridge and do not execute the complete upstream fixture suites.
