# Mesh/CAD conversion and hybrid editing

Spatial Modeling v0.1.0 is [publicly released](https://github.com/Nippar-DSBE/Spatial-Modeling/releases/tag/v0.1.0) with experimental in-memory conversion and CAD Vertex/Edge direct editing. The pinned SolidCore revision remains `d856327183691d55941b3abe3fb184583bfb6975`.

## Engine boundary

- Swift `MeshDocument` remains the free-deformation engine. CAD Vertex/Edge drags create a temporary document from actual B-rep boundaries and use its existing begin/update drag methods.
- Rust `spatial-mesh-cad` is a small original DSBE MIT adapter. It builds planar B-rep records and delegates construction, healing, merging and validation to SolidCore. The existing Apache-2.0 C ABI bridge owns the bodies and supplies the final intersection gate.
- CAD remains authoritative in Rust. A preview is temporary; successful reconstruction creates a real `solidcore_ops::Body`, otherwise the installed geometry and original Body are restored. There is no retained preview-only editing state.

## Mesh to CAD

1. Read logical vertices, boundary edges and ordered faces. Check that declared edges match the polygon boundaries.
2. Convert model-local RealityKit meters/Y-up to CAD millimeters/Z-up: `(x,y,z) -> (1000x,-1000z,1000y)`. Object display transforms are excluded.
3. Weld coincident points within **0.0001 mm**. Refuse welding that collapses a face boundary.
4. Retain each planar polygon. For a nonplanar polygon, project its boundary to a support frame and ear-clip that polygon only. These triangles become actual planar CAD faces with real shared edges, not merely display triangles. Unchanged planar quads/n-gons are not unconditionally triangulated.
5. Build f64 planes, straight shared edges, exact linear UV trim curves, oriented loops, one shell and two regions. `Brep::canonical` generates canonical indices/radial uses; every edge must have two uses.
6. `Body::from_record(..., false)` invokes the existing converter/import/healer path. If its healing changes topology in a way the adapter cannot map, refuse the result. Do not silently invent entity identities.
7. For an already-all-triangle input, native `stitch::merge_faces` coalesces compatible coplanar faces. Original n-gon input is retained by default. A welded 36-vertex/12-triangle cube test produces 8 vertices, 12 edges and 6 CAD faces.
8. Require `Body::check_solid`, `Body::check(Geometry)`, and the existing planar boundary-intersection guard. Reject detected orientation/volume, closure/manifold, degeneracy, self-intersection and near-contact failures before registering the Body. These are scoped validation gates, not a proof against every invalid input or a guarantee that a Boolean result matches user intent.
9. Retessellate with SolidCore, stage RealityKit resources, then commit. The previous formal Body remains owned through this transaction.

The adapter does not run a new plane-intersection/constraint solver. Its own math is limited to point welding, polygon frames/triangulation and record assembly. Curved-surface reconstruction and full local B-rep surgery remain future work.

## CAD to Mesh

The bridge exports canonical f64 B-rep vertices, actual edge endpoint pairs and outward face cycles from the same record used by tessellation. Each CAD record vertex/edge/face maps to the corresponding MeshDocument ID within that Body revision. Display-tessellation diagonals are not copied as logical edges.

`CADPolygonMesh` carries the conversion data independently of rendering. The editable document uses Float meters; hybrid editing also retains the original Double CAD anchors and adds the document's local displacement to them at reconstruction. This avoids replacing CAD coordinates with sampled display mesh vertices. A full CAD→Mesh→CAD round trip still has Float quantization in the ordinary Mesh session and is not promised bit-identical. Tests allow 0.0001 mm coordinate tolerance and small relative volume error.

Body/revision changes invalidate old selections. Numeric subentity IDs are scoped to a snapshot, not persistent names across reconstruction. Necessary adaptive-split CAD edges become real logical edges; unrelated display diagonals do not.

### Face identity

`sc_tessellate` assigns each CAD face its current B-rep record index. `from_record` exports faces in that order, and `CADPolygonMesh.document()` assigns the corresponding logical polygon the same index. This establishes correspondence within that Body snapshot; it does not store persistent source-face provenance in the ordinary Mesh document.

Mesh → CAD passes vertex positions and ordered polygon boundaries, not original face IDs. `to_body` assembles a new record, canonicalizes it and creates a new Body. Nonplanar polygons can split into multiple real CAD Faces, and all-triangle input can undergo coplanar merging. There is no parent/child face map or persistent naming across these operations or Booleans. Unchanged topology can happen to produce the same numeric indices, but that is not an identity guarantee.

`CADSession` checks object/body/revision when accepting selections and clears the selection when a new result is installed. `copy_with_order` maps a picked face to the copied kernel Body for Face Push / Pull; it is not cross-reconstruction persistent naming.

## Interaction and state

The existing native targeted DragGesture handles all three CAD element modes. Face mode keeps the prior SolidCore normal-offset preview. Vertex/Edge use a lightweight MeshDocument preview and update the existing LowLevelMesh buffers/parts/bounds. No CAD reconstruction runs for each Vertex/Edge frame.

On release, one asynchronous conversion is prepared from the drag-start body and absolute displacement. Invalid/stale/cancelled results are discarded; a valid result is staged and committed as one CAD history entry. Object scale/rotation is handled by converting the gesture to model-local coordinates first. The source geometry is not scaled into CAD dimensions.

Convert to CAD / Convert to Mesh are explicit actions, separate from mode switching. Existing destinations require confirmation. Sources remain unchanged. Destination geometry and display pose are replaceable and undoable together. A previously uninitialized CAD session initializes its normal Box baseline before import, so Undo can return to that Box. Mesh imports create a document with that imported shape as its Reset Shape baseline.

Mesh conversion history stores whole-document boundaries as needed, preserving the underlying position-history redo state across topology changes. CAD conversion uses the native Body snapshot stack and stores before/after display poses. No automatic conversion occurs during ordinary Mesh/CAD mode switching.

## Current scope and limits

- One closed planar/straight-edge shell, no cavities, one simple loop per face. Curves, face holes and arbitrary imported CAD are outside the initial conversion/hybrid scope. Existing ordinary CAD operations remain available where their own kernel contract allows them.
- 4–256 logical input vertices, 4–512 faces, at most 128 corners per face / 16384 face indices; CAD point coordinates must be finite and within the adapter budget. This is not a dense GLB/Tripo converter.
- The 0.0001 mm welding/planarity tolerance targets simple polyhedra at this scale. This prototype does not claim a manufacturing-grade or universal mesh-repair guarantee.
- Large deformations may fail projection, triangulation, healing or validity gates, or retessellate differently at commit. Failure restores the starting formal Body and gives a reason.
- Vertex and Edge edits can change face angles, and nonplanar original faces can become multiple real CAD faces. Coplanar merge and canonicalization can change IDs/counts; persistent feature naming is not implemented.
- Conversion changes only the destination after confirmation; it does not move/delete the source or bake Object Display Scale into dimensions.
- Modeling engines execute locally without a runtime network dependency. Basic device interactions and conversions have owner confirmation; offline regression, tracking-loss recovery, cold-start latency and extended stability remain separate, unconfirmed checks.

## Validation and timing

The existing host tests use actual Rust/SolidCore and macOS RealityKit. They cover Mesh Vertex/Edge/Face deformations to CAD, native Box round trips, adaptive splitting, welding/coplanar merging, variable-topology Mesh editing, destination confirmation, conversion/shape/Object Undo/Redo, rotated 200% hybrid drags, subsequent Boolean/Face Offset, invalid reconstruction, cancellation and handle release.

Separate fields record Swift preview, LowLevelMesh writing, native reconstruction+validation, tessellation and transfer times. Explicit conversion also measures total elapsed time. Logs are local evidence and are excluded from the source repository. Run `Scripts/check-hybrid-conversion.sh` for host regression and follow the hybrid checks in [Device testing](DEVICE_TESTING.md) for device-specific behavior. A passing host test or build is not a device acceptance result.

### Owner-reported device observations

On 2026-11-23 the owner confirmed basic Mesh Vertex/Edge/Face editing; CAD Vertex/Edge preview and committed B-rep reconstruction; Face Push / Pull; both explicit conversion directions; Object move/rotation; two-hand and slider scaling; Undo/Redo; and Mesh/CAD switching on Vision Pro. This report is distinct from the macOS/Rust host test results above.

Boolean Cut executes on device, including after deformation, but the owner has not yet established whether the resulting shape is the intended one. Its geometric correctness remains under validation. The earlier approximately 5.4 ms Boolean / 0.33 ms LowLevelMesh-update observations are reference timings only; they are not a detailed benchmark. Long-duration stability and detailed performance remain unverified. See [the verification matrix](DEVICE_TESTING.md#verification-record) for the exact scope and remaining checks.
