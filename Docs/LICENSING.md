# License scope and audit

The original application is distributed under the MIT License with the following copyright notice:

**Copyright (c) 2026 Design Studio Butterfly Effect**

Design Studio Butterfly Effect (DSBE) leads development and publication of Spatial Modeling. The root `LICENSE` applies to original Swift application code, project scripts, tests and documentation. Source headers identify this scope. These are the published license terms; they do not replace the independently retained third-party terms below.

The original Rust `spatial-mesh-cad` conversion crate in `Native/SolidCore/Conversion/` is also DSBE MIT code with its own license copy. It introduces no new external dependency.

## Independently retained terms

- `Native/SolidCore/Bridge/`: existing Apache-2.0 package declaration and `LICENSE`; no relicensing of the Rust bridge.
- `Native/SolidCore/Vendor/SolidCore/`: original Apache-2.0 license, NOTICE, attribution and per-source NVIDIA/SMLib provenance. Only the already-restricted workspace manifest has a packaging-change notice; kernel Rust source is unchanged.
- `Licenses/SolidCore/`: all original license/copyright files for the 33 direct/transitive locked dependencies, including compile-time dependencies. Dual-license texts, Zlib and Unicode additional terms remain intact.
- `Licenses/Rust-1.99.1/`: complete original standard-library notice and principal license texts, also bundled in the app. This upstream notice is a superset across platforms. Its Fortanix SGX MPL-2.0 entry concerns the SGX target, not the Apple visionOS target; optional LGPL alternatives do not change the independently licensed Swift code. No Rust compiler/toolchain binaries are published.
- Apple SDKs and system frameworks are platform-provided and are not redistributed.

`Scripts/audit-licenses.py` checks Cargo.lock coverage, declared licenses and byte equality of the bundled texts against cached/vendored originals. Runtime notice copies have provenance hashes and a matching app resource. Existing third-party copyright/NOTICE text is preserved, not replaced with DSBE attribution.

## Redistribution handling

Apache-2.0 source/object redistribution requires its license, applicable notices/attribution and prominent change notices on modified files. MIT requires retaining its copyright and permission text. Zlib requires accurate origin and change marking; Unicode-3.0 requires its notices. The package preserves all original alternative texts rather than silently deleting license options.

The published source repository excludes prebuilt native archives, upstream binary fixtures/test images, personal signing settings, caches and internal evidence. The reviewed dependencies' retained terms permit this source packaging with the independent app under MIT. Future dependencies and binary-release packaging require a fresh audit.

Original reference texts: [Apache-2.0](https://www.apache.org/licenses/LICENSE-2.0), [MIT](https://opensource.org/license/mit). See the bundled originals and `THIRD_PARTY_NOTICES.md` for component-specific terms.
