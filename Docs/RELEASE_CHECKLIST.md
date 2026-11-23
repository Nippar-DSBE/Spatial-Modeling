# v0.1.0 source publication checklist

Planned repository: **Nippar-DSBE/Spatial-Modeling**, **Public**.

Planned URL: https://github.com/Nippar-DSBE/Spatial-Modeling (not yet published).

Description: Native hybrid Mesh and CAD modeling for Apple Vision Pro, powered by Swift, RealityKit, and Rust.

Original DSBE implementation: MIT, Copyright (c) 2026 Design Studio Butterfly Effect. Independent third-party licenses remain unchanged.

## Included scope

Native visionOS app; Mesh/CAD modes; Vertex/Edge/Face direct editing; Mesh/B-rep conversion; on-device CAD; fixed-tool Boolean Cut; Face Push/Pull; Object Transform/Display Scale; Undo/Redo; original Rust conversion crate.

STL export is excluded. Planned roadmap features are not part of v0.1.0.

## Before publication

- Review README, current limitations and the actual Vision Pro behavior using `DEVICE_TESTING.md`.
- Verify original dependency LICENSE/NOTICE texts, pinned versions and the packaging-change notice in the vendored workspace manifest. Retain all per-file provenance headers.
- Prepare a source-only local candidate with `Scripts/prepare-release.py`. Replacing an existing marked candidate needs explicit owner approval and `--replace-approved-candidate`; this never authorizes Git operations or publication.
- Review `PUBLIC_FILES.json`, then run `Scripts/audit-release.py`. The manifest includes planned repository metadata; its authorization and hardware-pending fields are review bookkeeping, not test certificates.
- Copy that candidate to a separate empty directory and rebuild the Rust device library and unsigned visionOS app. Do not copy the working tree's generated XCFramework. Use an empty Cargo target directory and fresh DerivedData, with cached locked source dependencies.
- Keep personal signing settings, credentials, absolute machine paths, backups, test evidence, caches and generated archives out of publication. Scripts can create ignored local evidence after cloning.
- Confirm GitHub CLI authentication separately from browser sign-in. Do not place tokens in project files or shell arguments.
- Obtain explicit final owner approval before repository creation, git commit, push, tags or GitHub releases.

A successful unsigned build does not establish physical-device operation or imply publication authorization.
