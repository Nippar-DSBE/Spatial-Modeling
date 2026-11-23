# Release status and maintenance checklist

Repository: [Nippar-DSBE/Spatial-Modeling](https://github.com/Nippar-DSBE/Spatial-Modeling), **Public**.

[v0.1.0](https://github.com/Nippar-DSBE/Spatial-Modeling/releases/tag/v0.1.0) was published on 2026-11-23. Its tag and Release remain the original published snapshot. The owner subsequently added a demo to main's README; preserve that media when preparing documentation updates.

Description: Native hybrid Mesh and CAD modeling for Apple Vision Pro, powered by Swift, RealityKit, and Rust.

Original DSBE implementation: MIT, Copyright (c) 2026 Design Studio Butterfly Effect. Independent third-party licenses remain unchanged.

## v0.1.0 scope and verification

The release includes the native visionOS app; Mesh/CAD modes; Vertex/Edge/Face direct editing; Mesh/B-rep conversion; on-device CAD; fixed-tool Boolean Cut; Face Push/Pull; Object Transform/Display Scale; Undo/Redo; and the original Rust conversion crate.

STL export is not implemented in v0.1.0. **STL Export / 3D Printing** is Roadmap work, not a current capability.

`Native/SolidCore/PHASE3.json` and `PHASE32.json` are historical implementation/build provenance; their preparation-time publication fields do not describe the current repository status.

The original source-only package passed the recorded host checks and unsigned device-target builds. Owner-reported device checks are documented separately in [Device testing](DEVICE_TESTING.md#verification-record). Boolean Cut executes, but its intended output geometry, including after deformation, remains under validation. Neither release publication nor the demo certifies all device tests, long-duration stability or performance.

## Future maintenance and release checks

- Start from the latest remote main, preserve owner-added media and review the diff. Do not regenerate an old source snapshot over newer repository content.
- Keep README, build instructions, hybrid limits, verification records and third-party notices consistent. Record owner/device observations separately from host-test results, with explicit scope and remaining uncertainty.
- Retain dependency LICENSE/NOTICE, pinned versions, upstream links, per-file provenance and packaging-change notices. Audit new dependencies before distribution.
- For a future source-only release, `Scripts/prepare-release.py` creates local staging. It is still hard-coded to v0.1.0: do not run it for a new version without separately updating and reviewing the release tooling. Its approval fields and local manifests are bookkeeping, not hardware certificates.
- Rebuild a future package from an isolated copy without a prebuilt XCFramework, using empty Cargo outputs and fresh DerivedData. Preserve main's demo and keep generated outputs/private signing settings out of publication.
- Review credentials, machine paths and media privacy before any subsequent publication. Confirm CLI authentication separately from browser sign-in.
- Leave existing published tags and Releases unchanged unless explicitly authorized. Documentation corrections on main do not require rewriting a version tag.

This checklist records status and workflow; it does not itself grant permission to commit, push, retag or publish a new release.
