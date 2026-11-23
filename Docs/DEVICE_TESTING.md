# v0.1.0 Vision Pro release checklist

Hardware verification remains the owner's responsibility. Build success and macOS tests do not establish gesture recognition quality on Vision Pro.

1. Build/install with your signing Team. In Mesh, open mixed ImmersiveSpace and verify initial placement, stationary world placement, Vertex/Edge/Face drag and Undo/Redo.
2. Select Object. Pinch the body or its white lower handle and move it. Confirm element handles are disabled and no geometry deforms. Use two hands to enlarge/shrink and rotate, including simultaneous move/scale/rotation and transitions from one to two hands. Releasing the combined gesture should create one history item, with no position/scale jump.
3. Drag the 10–300% scale slider. Test 1%, 100%, 200%, 1000% numeric values, Apply/Return, 100% button, and rejection of zero, negative, NaN, Infinity and out-of-range values. Slider position clamps its UI to its range when the actual numeric scale is outside it; the actual percentage remains visible.
4. Verify rotation/scale stay centered on the current model bounds. Reset Transform restores initial pose; Reset Shape preserves the display transform. Undo/Redo should reverse shape and Object operations in chronological order. Test Undo followed by a new edit clears the visible Redo branch.
5. Switch to CAD, generate/reset the 300mm box and set Display Scale to 200%. CAD Dimensions should remain 300 × 300 × 300mm. Move/rotate the display, choose Face, and push/pull: 50mm movement in scene space along the normal should represent 25mm CAD displacement at 200% scale.
6. Perform Boolean Cut, then face push/pull, Undo/Redo and Reset Shape. Verify CAD Vertex/Edge select actual B-rep elements and use the hybrid mesh preview / CAD reconstruction path described in `HYBRID_MODELING.md`. Reject a collapsing/inward-invalid face move without replacing the last committed body.
7. Alternate Mesh/CAD repeatedly. Each geometry, history and transform should be retained. During Object/CAD/element edits, mode and selection pickers should be locked. Cancel via app backgrounding and test reopening the space.
8. Disable networking and repeat Box/Cut/PushPull/Object operations. Confirm timings and memory remain acceptable across repeated actions. CAD metrics are logged in the app's Application Support directory.
9. Capture approved screenshots/video into `Docs/Media/` only after checking them for personal surroundings and other sensitive content. Replace the README media placeholder.
10. The original-code MIT license and DSBE copyright have been approved. Rebuild the release candidate, rerun license/security audits, review its manifest and only then authorize GitHub creation/publication in a separate instruction.

## Phase 3.2 conversion and hybrid checks

1. In Mesh Mode, deform a cube vertex, then Convert to CAD. If the CAD session already exists, cancel the confirmation once and verify nothing was replaced; confirm on the second try. The source mesh must remain available unchanged.
2. Verify the converted CAD retains planar quads and splits only nonplanar faces. Switch CAD Vertex/Edge and pinch-drag: preview should follow immediately; release should commit a new formal Body. Test Undo/Redo per drag.
3. Convert to Mesh, confirm replacement, and verify no tessellation diagonals became logical edges. Edit its vertices/edges/faces and convert back. Undo the conversion and the edits around it to verify history and display pose retention.
4. At 200% display scale with rotation/translation applied, repeat both conversions and hybrid drags. CAD dimensions must not double. Boolean Cut and Face Push/Pull must work on the committed result.
5. Try collapsing a vertex onto its neighbor or making a self-intersecting mesh. Failed conversion must display a reason and preserve the formal Body/destination. No preview-only result should remain after failure. Test tracking-loss cancellation and app backgrounding.
6. Review the timing fields and CSV (`spatial-modeling-cad-phase32-metrics.csv`). Perform the same checks offline. The owner authorized a Phase 3.2 source-candidate refresh separately. Hardware checks and explicit final approval are still required before publication.
