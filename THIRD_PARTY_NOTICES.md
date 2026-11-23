# Third-party notices

The original application MIT license does not replace any third-party license.

## SolidCore and its kernel origin

Source: https://github.com/tangency-labs/solidcore  
Pinned commit: `d856327183691d55941b3abe3fb184583bfb6975`  
Kernel: `solidcore` 1.0.1; supporting crates 0.1.0, Apache-2.0.

The original Apache license, NOTICE, ATTRIBUTION and per-source provenance headers are preserved in the vendored tree and `Licenses/SolidCore/`. SolidCore ports NVIDIA USD BRep's SMLib / SM_API, v1.0.1 / commit `3fd5b95`, source https://github.com/NVIDIA-Omniverse/usd-brep. Only the five library crates are built.

The vendored workspace Cargo.toml was restricted to those five crates and the unrelated goldens package profile entry was removed; a prominent modification notice is in that file. Kernel Rust source is unchanged. The public source candidate omits upstream fixture data/images. No SolidCraft application UI, renderer, theme, logo or brand asset is redistributed. References in source comments and attribution identify origin.

The local C ABI bridge is independent integration code retaining its declared Apache-2.0 license (`Native/SolidCore/Bridge/LICENSE`). Phase 3 added offset/topology/validation APIs and a planar boundary guard; Phase 3.2 adds polygon conversion APIs and the separate MIT adapter; no upstream kernel Rust source is modified.

### Original kernel NOTICE

```text
solidcore
Copyright (c) 2026 The solidcore contributors

This product is a Rust port (a derivative work) of the SMLib and SM_API
components of USD BRep, https://github.com/NVIDIA-Omniverse/usd-brep
(v1.0.1, commit 3fd5b95), licensed under the Apache License, Version 2.0.
See ATTRIBUTION.md for exactly which upstream material is used.

The upstream work carries the following notice:

  USD BRep is Copyright (c) 2020-2026, NVIDIA CORPORATION & AFFILIATES. All
  rights reserved. NVIDIA-authored portions of this product are licensed under
  the Apache License, Version 2.0, except where otherwise noted.

The upstream SMLib and SM_API source files carry the SPDX header:

  SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
  SPDX-License-Identifier: Apache-2.0

Upstream third-party notices (THIRD_PARTY_NOTICES.md at the pinned commit) cover
OpenUSD, oneTBB, hwloc, MaterialX, OpenSubdiv, CPython, HACL*, pybind11, the
UsdSolid proposals, usd-validation-nvidia, the repo bootstrap scripts and optional
Python GUI tooling. None of those components is part of SMLib or SM_API, and none
is used, ported or redistributed by solidcore, so no further third-party notices
apply.

Modifications: the C++ sources were translated to Rust and restructured (arena
topology, typed ids, error values instead of status codes, explicit kernel
state instead of a global context). Each ported Rust file names the upstream
file(s) it derives from in its header.

```

## Locked direct and transitive Cargo dependencies

`Native/SolidCore/Cargo.lock` covers 35 packages: the local Apache-2.0 bridge, the DSBE-owned MIT `spatial-mesh-cad` conversion crate, and the following 33 third-party dependencies, including build/proc-macro dependencies. Every listed license/notice is copied without alteration from the cached source or vendored original; `Scripts/audit-licenses.py` verifies coverage and byte equality.

| Package | Version | Declared license | Source | Original license/notice files |
| --- | --- | --- | --- | --- |
| allocator-api2 | 0.2.21 | MIT OR Apache-2.0 | [repository](https://github.com/zakarumych/allocator-api2) | [LICENSE-APACHE](Licenses/SolidCore/allocator-api2-0.2.21/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/allocator-api2-0.2.21/LICENSE-MIT) |
| autocfg | 1.5.1 | Apache-2.0 OR MIT | [repository](https://github.com/cuviper/autocfg) | [LICENSE-APACHE](Licenses/SolidCore/autocfg-1.5.1/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/autocfg-1.5.1/LICENSE-MIT) |
| crossbeam-deque | 0.8.8 | MIT OR Apache-2.0 | [repository](https://github.com/crossbeam-rs/crossbeam) | [LICENSE-APACHE](Licenses/SolidCore/crossbeam-deque-0.8.8/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/crossbeam-deque-0.8.8/LICENSE-MIT) |
| crossbeam-epoch | 0.9.21 | MIT OR Apache-2.0 | [repository](https://github.com/crossbeam-rs/crossbeam) | [LICENSE-APACHE](Licenses/SolidCore/crossbeam-epoch-0.9.21/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/crossbeam-epoch-0.9.21/LICENSE-MIT) |
| crossbeam-utils | 0.8.23 | MIT OR Apache-2.0 | [repository](https://github.com/crossbeam-rs/crossbeam) | [LICENSE-APACHE](Licenses/SolidCore/crossbeam-utils-0.8.23/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/crossbeam-utils-0.8.23/LICENSE-MIT) |
| either | 1.19.0 | MIT OR Apache-2.0 | [repository](https://github.com/rayon-rs/either) | [LICENSE-APACHE](Licenses/SolidCore/either-1.19.0/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/either-1.19.0/LICENSE-MIT) |
| equivalent | 1.0.3 | Apache-2.0 OR MIT | [repository](https://github.com/indexmap-rs/equivalent) | [LICENSE-APACHE](Licenses/SolidCore/equivalent-1.0.3/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/equivalent-1.0.3/LICENSE-MIT) |
| foldhash | 0.2.0 | Zlib | [repository](https://github.com/orlp/foldhash) | [LICENSE](Licenses/SolidCore/foldhash-0.2.0/LICENSE) |
| hashbrown | 0.16.1 | MIT OR Apache-2.0 | [repository](https://github.com/rust-lang/hashbrown) | [LICENSE-APACHE](Licenses/SolidCore/hashbrown-0.16.1/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/hashbrown-0.16.1/LICENSE-MIT) |
| itoa | 1.0.19 | MIT OR Apache-2.0 | [repository](https://github.com/dtolnay/itoa) | [LICENSE-APACHE](Licenses/SolidCore/itoa-1.0.19/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/itoa-1.0.19/LICENSE-MIT) |
| memchr | 2.8.3 | Unlicense OR MIT | [repository](https://github.com/BurntSushi/memchr) | [COPYING](Licenses/SolidCore/memchr-2.8.3/COPYING), [LICENSE-MIT](Licenses/SolidCore/memchr-2.8.3/LICENSE-MIT), [UNLICENSE](Licenses/SolidCore/memchr-2.8.3/UNLICENSE) |
| num-traits | 0.2.19 | MIT OR Apache-2.0 | [repository](https://github.com/rust-num/num-traits) | [LICENSE-APACHE](Licenses/SolidCore/num-traits-0.2.19/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/num-traits-0.2.19/LICENSE-MIT) |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 | [repository](https://github.com/dtolnay/proc-macro2) | [LICENSE-APACHE](Licenses/SolidCore/proc-macro2-1.0.107/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/proc-macro2-1.0.107/LICENSE-MIT) |
| quote | 1.0.47 | MIT OR Apache-2.0 | [repository](https://github.com/dtolnay/quote) | [LICENSE-APACHE](Licenses/SolidCore/quote-1.0.47/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/quote-1.0.47/LICENSE-MIT) |
| rayon | 1.12.0 | MIT OR Apache-2.0 | [repository](https://github.com/rayon-rs/rayon) | [LICENSE-APACHE](Licenses/SolidCore/rayon-1.12.0/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/rayon-1.12.0/LICENSE-MIT) |
| rayon-core | 1.13.0 | MIT OR Apache-2.0 | [repository](https://github.com/rayon-rs/rayon) | [LICENSE-APACHE](Licenses/SolidCore/rayon-core-1.13.0/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/rayon-core-1.13.0/LICENSE-MIT) |
| robust | 1.2.0 | MIT OR Apache-2.0 | [repository](https://github.com/georust/robust) | [LICENSE-APACHE](Licenses/SolidCore/robust-1.2.0/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/robust-1.2.0/LICENSE-MIT) |
| serde | 1.0.229 | MIT OR Apache-2.0 | [repository](https://github.com/serde-rs/serde) | [LICENSE-APACHE](Licenses/SolidCore/serde-1.0.229/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/serde-1.0.229/LICENSE-MIT) |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | [repository](https://github.com/serde-rs/serde) | [LICENSE-APACHE](Licenses/SolidCore/serde_core-1.0.229/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/serde_core-1.0.229/LICENSE-MIT) |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 | [repository](https://github.com/serde-rs/serde) | [LICENSE-APACHE](Licenses/SolidCore/serde_derive-1.0.229/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/serde_derive-1.0.229/LICENSE-MIT) |
| serde_json | 1.0.154 | MIT OR Apache-2.0 | [repository](https://github.com/serde-rs/json) | [LICENSE-APACHE](Licenses/SolidCore/serde_json-1.0.154/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/serde_json-1.0.154/LICENSE-MIT) |
| smallvec | 1.16.6 | MIT OR Apache-2.0 | [repository](https://github.com/smallvec/smallvec) | [LICENSE-APACHE](Licenses/SolidCore/smallvec-1.16.6/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/smallvec-1.16.6/LICENSE-MIT) |
| solidcore | 1.0.1 | Apache-2.0 | [repository](https://github.com/tangency-labs/solidcore) | [LICENSE](Licenses/SolidCore/solidcore-1.0.1/LICENSE), [NOTICE](Licenses/SolidCore/solidcore-1.0.1/NOTICE) |
| solidcore-convert | 0.1.0 | Apache-2.0 | [repository](https://github.com/tangency-labs/solidcore) | [SolidCore-LICENSE](Licenses/SolidCore/SolidCore-LICENSE), [SolidCore-NOTICE](Licenses/SolidCore/SolidCore-NOTICE) |
| solidcore-ops | 0.1.0 | Apache-2.0 | [repository](https://github.com/tangency-labs/solidcore) | [SolidCore-LICENSE](Licenses/SolidCore/SolidCore-LICENSE), [SolidCore-NOTICE](Licenses/SolidCore/SolidCore-NOTICE) |
| solidcore-record | 0.1.0 | Apache-2.0 | [repository](https://github.com/tangency-labs/solidcore) | [SolidCore-LICENSE](Licenses/SolidCore/SolidCore-LICENSE), [SolidCore-NOTICE](Licenses/SolidCore/SolidCore-NOTICE) |
| solidcore-tess | 0.1.0 | Apache-2.0 | [repository](https://github.com/tangency-labs/solidcore) | [SolidCore-LICENSE](Licenses/SolidCore/SolidCore-LICENSE), [SolidCore-NOTICE](Licenses/SolidCore/SolidCore-NOTICE) |
| spade | 2.15.1 | MIT OR Apache-2.0 | [repository](https://github.com/Stoeoef/spade) | [LICENSE-APACHE](Licenses/SolidCore/spade-2.15.1/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/spade-2.15.1/LICENSE-MIT) |
| syn | 3.0.10 | MIT OR Apache-2.0 | [repository](https://github.com/dtolnay/syn) | [LICENSE-APACHE](Licenses/SolidCore/syn-3.0.10/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/syn-3.0.10/LICENSE-MIT) |
| thiserror | 2.0.21 | MIT OR Apache-2.0 | [repository](https://github.com/dtolnay/thiserror) | [LICENSE-APACHE](Licenses/SolidCore/thiserror-2.0.21/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/thiserror-2.0.21/LICENSE-MIT) |
| thiserror-impl | 2.0.21 | MIT OR Apache-2.0 | [repository](https://github.com/dtolnay/thiserror) | [LICENSE-APACHE](Licenses/SolidCore/thiserror-impl-2.0.21/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/thiserror-impl-2.0.21/LICENSE-MIT) |
| unicode-ident | 1.0.27 | (MIT OR Apache-2.0) AND Unicode-3.0 | [repository](https://github.com/dtolnay/unicode-ident) | [LICENSE-APACHE](Licenses/SolidCore/unicode-ident-1.0.27/LICENSE-APACHE), [LICENSE-MIT](Licenses/SolidCore/unicode-ident-1.0.27/LICENSE-MIT), [LICENSE-UNICODE](Licenses/SolidCore/unicode-ident-1.0.27/LICENSE-UNICODE) |
| zmij | 1.0.23 | MIT | [repository](https://github.com/dtolnay/zmij) | [LICENSE-MIT](Licenses/SolidCore/zmij-1.0.23/LICENSE-MIT) |

All alternative license texts are preserved for dual-licensed crates. `unicode-ident` additionally requires Unicode-3.0 notices; `foldhash` uses Zlib origin/change-notice conditions. No original dependency source is modified here. Copyright and attribution text, including upstream authors' names, remains intact.

## Local conversion crate

`Native/SolidCore/Conversion/` is original DSBE integration code under MIT, Copyright (c) 2026 Design Studio Butterfly Effect. Its LICENSE matches the root MIT license. It uses the existing third-party crates; Phase 3.2 adds no registry dependency. The Rust bridge and all vendored sources retain their existing licenses.

## Rust standard-library runtime

The generated static library links Rust's standard library. The complete original Rust 1.99.1 standard-library copyright/third-party notice is retained as [`Licenses/Rust-1.99.1/COPYRIGHT-library.html`](Licenses/Rust-1.99.1/COPYRIGHT-library.html), with its referenced principal license texts and provenance. It is also bundled in the app as `RustStandardLibraryNotices.html`. The notice is an upstream superset covering multiple targets; inclusion is not a claim that every listed platform dependency is linked on visionOS. Rust toolchain binaries themselves are not part of the source candidate.

Rust's standard-library notice states Apache-2.0 OR MIT generally, with exceptions identified in that original notice, including Unicode data. Keep the complete notice when distributing rebuilt binaries. Apple system frameworks and the SDK are platform-provided and are not redistributed by this repository.

## Original application license

Original Swift app, scripts, tests and documentation: MIT, Copyright (c) 2026 Design Studio Butterfly Effect. See [LICENSE](LICENSE). The independently packaged Rust bridge retains Apache-2.0, and third-party components retain their existing terms. See [license scope](Docs/LICENSING.md).

Redistribution references: [Apache-2.0 section 4](https://www.apache.org/licenses/LICENSE-2.0), [MIT text](https://opensource.org/license/mit). Bundled original texts control each dependency's actual terms.
