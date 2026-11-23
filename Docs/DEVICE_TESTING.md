# Vision Pro verification record and regression checklist

Spatial Modeling v0.1.0 is public. This document separates **owner-reported Vision Pro observations**, **recorded host/build results**, and **checks that still need device evidence**. Publication, a successful build or a demo video is not a blanket test pass.

## Verification record

Device observations below were supplied by the owner on **2026-11-23**. They are manual functional checks, not an independently reproduced or exhaustive regression suite. No additional device tests were run during this documentation audit.

| Area | Vision Pro status | Confirmed scope / remaining uncertainty |
| --- | --- | --- |
| Mesh Vertex / Edge / Face | Owner-confirmed | Basic direct editing in all three modes. Degenerate shapes, tracking loss and extended sessions are not covered by this confirmation. |
| CAD Vertex / Edge | Owner-confirmed | Direct manipulation and deformation committed after B-rep reconstruction. This does not establish validity for arbitrary solids or persistent Face IDs. |
| CAD Face Push / Pull | Owner-confirmed | Basic face interaction. Behavior after every deformation/Boolean and under every transformed pose is not individually confirmed. |
| Mesh → CAD | Owner-confirmed | Basic explicit conversion. Not a guarantee for arbitrary meshes. |
| CAD → Mesh | Owner-confirmed | Basic explicit conversion. Dense/curved bodies, face holes and internal cavities remain outside the implementation scope. |
| Object move / rotation | Owner-confirmed | Basic whole-object movement and rotation. Simultaneous gesture transitions and cancellation remain separate checks. |
| Two-hand scaling | Owner-confirmed | Basic magnification gesture. One-/two-hand transitions, simultaneous rotation and range extremes are not individually confirmed. |
| Slider scaling | Owner-confirmed | Basic slider-based scaling. Numeric entry, invalid values and 1% / 1000% extremes are not confirmed by this report. |
| Undo / Redo | Owner-confirmed | Basic operation. All interleaved shape/Object/conversion history branches are not individually confirmed on device. |
| Mesh / CAD switching | Owner-confirmed | Basic switching. Busy-operation blocking, tracking loss and repeated lifecycle recovery remain separate checks. |
| Boolean Cut, including after deformation | Validation ongoing | Executes on device. The owner has not yet established whether the resulting shape matches the intended cut; do not mark geometric correctness as passed. |
| Long-duration stability | Unverified | No extended-session stability result supplied. |
| Detailed performance | Unverified | No controlled latency, frame-time or memory-growth benchmark supplied. |

The earlier owner-reported **Boolean ≈5.4 ms** and **LowLevelMesh update ≈0.33 ms** readings are retained as reference observations. They are not a controlled benchmark, a guarantee for other operations or evidence that the Boolean result is geometrically correct.

### Recorded host and build results

The v0.1.0 preparation recorded successful Rust host tests, macOS RealityKit integration checks and a clean unsigned physical-device-target build using Rust 1.99.1, Xcode 27.0 (27A266a), visionOS 27.0 SDK and `aarch64-apple-visionos`. The native XCFramework and app compiled/linked successfully. No Simulator build or Runtime download was part of that verification.

Host coverage includes Mesh direct edits; CAD Box/Boolean/Face Offset; Mesh/CAD round trips; nonplanar-face splitting; rotated 200% coordinate conversions; history; invalid-input rollback; stale-target rejection; and handle cleanup. Those results do **not** establish the same outcomes on Vision Pro or prove every Boolean matches modeling intent. The full upstream fixture suites were not run as part of this app's verification.

See `Tests/HybridConversionChecks.swift`, `Tests/CADDirectChecks.swift`, `Tests/ObjectTransformChecks.swift`, `Tests/ModeIntegrationChecks.swift` and `Tests/MeshCoreChecks.swift` for host assertions. These tests were not rerun during this documentation-only audit.

## Device regression checklist

The list below specifies checks to perform; it is **not** a list of completed tests. Basic owner-confirmed operations are recorded above. Mark a detailed scenario passed only after recording that specific observation, build/commit, device/visionOS version and outcome.

- [ ] Build/install with personal signing settings. Verify initial mixed-space placement remains fixed in the world while the head moves; inspect handle/display alignment during Mesh Vertex/Edge/Face drags.
- [ ] Exercise Object movement, simultaneous two-hand scale/rotation and one-/two-hand transitions. Check for jumps and unintended element edits; verify one gesture produces one history item.
- [ ] Exercise the 10–300% slider and numeric 1%, 100%, 200%, 1000% entry. Test Apply/Return, 100% button and rejection of zero, negative, NaN, Infinity and out-of-range values.
- [ ] Check model-center rotation/scaling, separate Reset Shape/Reset Transform, chronological interleaved shape/Object Undo/Redo, and Redo invalidation after a new edit.
- [ ] At 200% display scale with rotation applied, confirm a 300 mm CAD Box retains its formal dimensions. For Face Push / Pull, 50 mm world movement along the scaled normal should produce 25 mm CAD displacement.
- [ ] For Boolean Cut, compare the result against the known fixed tool and target. Check the cut's position, dimensions, retained material and visible surfaces. Record expected versus actual geometry, not merely that the button completes.
- [ ] Repeat Boolean Cut after Vertex/Edge deformation, conversion and Face Push / Pull. Check the intended result and then verify subsequent operations, Undo/Redo and Reset. Boolean correctness remains open until these comparisons are recorded.
- [ ] Repeatedly alternate Mesh/CAD; verify geometry, history, selection and display-pose retention. Check picker locks during active edits and safe cancellation/reopening across app lifecycle events.
- [ ] Disable networking and repeat core operations. Measure repeated-operation timing, memory growth, cold starts and extended-session stability separately; retain the build and device context.
- [ ] Keep the owner-added README demo intact. Review future recordings for private surroundings, notifications and account information; a clip does not substitute for the checklist.

## Conversion and hybrid regression

Basic conversions and committed CAD Vertex/Edge edits are owner-confirmed. The combinations and failure cases below still need their own device records.

- [ ] Deform a Mesh cube vertex, Convert to CAD, cancel destination replacement once, then confirm it. Verify the source stays unchanged.
- [ ] Inspect retained planar quads and real CAD Face splitting where polygons became nonplanar. Verify preview responsiveness, valid commit and one Undo/Redo action per drag.
- [ ] Convert CAD → Mesh → CAD. Confirm display-tessellation diagonals do not become logical edges, and test topology replacement and history across surrounding edits.
- [ ] Repeat at 200% display scale with translation/rotation. Confirm dimensions are not doubled, then check Face Push / Pull and the intended Boolean result independently.
- [ ] Try vertex collapse and self-intersection. Verify failure messages, preservation of the previous formal Body/destination and complete rollback of the temporary preview. Test tracking loss and app backgrounding.
- [ ] Review per-stage timing and `spatial-modeling-cad-phase32-metrics.csv` separately from visual correctness. Record sustained behavior and repeat offline.

## Recording an outcome

For a new device check, record the date, source commit/build, device and visionOS version, exact starting shape and steps, expected/actual outcome, and any timing/memory context. Use separate labels for **owner-confirmed**, **validation ongoing**, **unverified** and **failed**. Update this record and the README summary together. Keep the original v0.1.0 tag and Release unchanged when documenting later observations on main.
