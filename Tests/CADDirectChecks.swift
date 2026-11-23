// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import RealityKit
import simd
import SolidCoreProbe

@main struct CADDirectChecks {
    @MainActor static func all(_ entity: Entity) -> [Entity] { [entity] + entity.children.flatMap(all) }
    @MainActor static func handle(_ w: WorkspaceModel, _ mode: CADSelectionMode, id: UInt32? = nil) -> Entity {
        all(w.cad.renderer.root).first {
            guard let t = $0.components[CADTopologyTarget.self] else { return false }
            return t.selection.mode == mode && (id == nil || t.selection.id == id)
        }!
    }
    static func volume(_ id: UInt64) -> Double {
        var v = 0.0; precondition(sc_body_volume(id, &v) == 0); return v
    }
    @MainActor static func action(_ w: WorkspaceModel, _ a: CADAction) async {
        let ok = await w.performCAD(a); precondition(ok, w.cad.errorMessage ?? "CAD action failed")
    }
    @MainActor static func push(_ w: WorkspaceModel, mm: Double, id: UInt32? = nil) async {
        let e = handle(w, .face, id: id)
        let target = e.components[CADTopologyTarget.self]!
        let face = w.cad.committedMesh!.topology.first { $0.selection == target.selection }!
        let baseline = w.cad.bodyID
        precondition(w.beginCADInput(entity: e, at: .zero, activation: w.activation))
        precondition(!w.canSwitchModes && !w.setMode(.mesh))
        let end = CADCoordinateConversion.offsetMeters(mm, along: face.normal)
        // Tangential displacement must not change the projected mm amount.
        let tangent = abs(face.normal.x) < 0.9 ? simd_normalize(simd_cross(face.normal, SIMD3<Float>(1,0,0))) : simd_normalize(simd_cross(face.normal, SIMD3<Float>(0,1,0)))
        w.updateCADInput(to: end * 0.5, activation: w.activation)
        await w.cad.waitForPreview()
        w.updateCADInput(to: end + tangent * 0.03, activation: w.activation)
        await w.cad.waitForPreview()
        precondition(w.cad.isDragging && w.cad.previewValid, w.cad.errorMessage ?? "preview failed")
        precondition(w.cad.bodyID == baseline, "Preview must not commit/history per frame")
        precondition(all(w.cad.renderer.root).contains { $0 === e }, "Original gesture Entity survives preview")
        precondition(abs(w.cad.distanceMM - mm) < 0.01)
        w.finishCADInput(at: end + tangent * 0.03, activation: w.activation)
        await w.cad.waitForPreview()
        precondition(!w.cad.isEditing && w.cad.bodyID != baseline)
        precondition(sc_body_validate(w.cad.bodyID) == 0)
        precondition(!w.selectCAD(e, activation: w.activation), "Pre-edit entity is stale after commit")
        if let m = w.cad.measurements {
            print(String(format: "MEASURE mm=%+.1f CAD=%.3f Tess=%.3f Transfer=%.3f LowLevelMesh=%.3f ms faces=%d triangles=%d", mm, m.directModelMS, m.tessellationMS, m.transferMS, m.lowLevelMeshMS, m.faces, m.triangles))
        }
    }
    @MainActor static func main() async throws {
        CADTopologyTarget.registerComponent(); CADFaceTarget.registerComponent(); EditTargetComponent.registerComponent()
        let w = WorkspaceModel(recordCADMeasurements: false)
        try w.prepareScene(); w.immersiveState = .open
        w.placeSessions(at: Transform(translation: [0,1.2,-0.9]))
        let meshPositions = w.mesh.document.positions
        precondition(w.setMode(.cad)); await action(w, .generate)
        let topology = w.cad.committedMesh!.topology
        precondition(topology.filter { $0.selection.mode == .vertex }.count == 8)
        precondition(topology.filter { $0.selection.mode == .edge }.count == 12, "No triangulation diagonals")
        precondition(topology.filter { $0.selection.mode == .face }.count == 6)
        for mode in CADSelectionMode.allCases {
            w.setCADSelectionMode(mode)
            precondition(w.selectCAD(handle(w, mode), activation: w.activation))
            precondition(all(w.cad.renderer.root).filter { $0.components[CADTopologyTarget.self] != nil && $0.isEnabledInHierarchy }.allSatisfy { $0.components[CADTopologyTarget.self]!.selection.mode == mode })
            if mode != .face {
                precondition(w.beginCADInput(entity: handle(w, mode), at: .zero, activation: w.activation))
                w.cad.cancelDrag();await w.cad.waitForPreview()
            }
        }
        let staleEntity = handle(w, .face)
        let original = w.cad.bodyID
        await push(w, mm: 25)
        precondition(abs(volume(w.cad.bodyID) - 29_250_000) < 2)
        let editedVolume = volume(w.cad.bodyID)
        await action(w, .undo); precondition(w.cad.bodyID == original && w.cad.canRedo)
        await action(w, .redo); precondition(abs(volume(w.cad.bodyID) - editedVolume) < 1)
        await action(w, .undo)
        await action(w, .cut)
        precondition(!w.cad.canRedo && w.cad.measurements!.faces == 9)
        let cutVolume = volume(w.cad.bodyID)
        var volumes = [cutVolume]
        for mm in [10.0,-5.0,15.0] { await push(w, mm: mm); volumes.append(volume(w.cad.bodyID)) }
        for expected in volumes.dropLast().reversed() { await action(w, .undo); precondition(abs(volume(w.cad.bodyID) - expected) < 2) }
        for expected in volumes.dropFirst() { await action(w, .redo); precondition(abs(volume(w.cad.bodyID) - expected) < 2) }
        // Reject a collapsing inward offset without adding a history entry.
        let before = w.cad.bodyID; let revision = w.cad.revision
        let entity = handle(w, .face)
        let element = w.cad.committedMesh!.topology.first { $0.selection == entity.components[CADTopologyTarget.self]!.selection }!
        precondition(w.beginCADInput(entity: entity, at: .zero, activation: w.activation))
        let invalid = CADCoordinateConversion.offsetMeters(-500, along: element.normal)
        w.finishCADInput(at: invalid, activation: w.activation, entity: staleEntity)
        precondition(w.cad.isDragging, "Stale gesture-end entity must not finish the current drag")
        w.updateCADInput(to: invalid, activation: w.activation); await w.cad.waitForPreview()
        precondition(!w.cad.previewValid)
        w.finishCADInput(at: invalid, activation: w.activation); await w.cad.waitForPreview()
        precondition(w.cad.bodyID == before && w.cad.revision == revision)
        // Cancel immediately while a request is in flight.
        precondition(w.beginCADInput(entity: entity, at: .zero, activation: w.activation))
        w.updateCADInput(to: CADCoordinateConversion.offsetMeters(12, along: element.normal), activation: w.activation)
        w.cad.cancelDrag(); await w.cad.waitForPreview()
        precondition(w.cad.bodyID == before && w.cad.revision == revision)
        // Coalesce many requests and commit only the final absolute displacement.
        precondition(w.beginCADInput(entity: entity, at: .zero, activation: w.activation))
        for i in 1...100 { w.updateCADInput(to: CADCoordinateConversion.offsetMeters(Double(i)/10, along: element.normal), activation: w.activation) }
        w.finishCADInput(at: CADCoordinateConversion.offsetMeters(10, along: element.normal), activation: w.activation)
        await w.cad.waitForPreview(); precondition(w.cad.revision > revision)
        await action(w, .undo); precondition(w.cad.bodyID == before, "100 preview inputs make one history item")
        let stale = CADCommand(objectID: w.cad.objectID, revision: revision, operation: .reset)
        let decoded = try JSONDecoder().decode(CADCommand.self, from: JSONEncoder().encode(stale))
        let rejected = await w.cad.execute(decoded) { true }; precondition(!rejected)
        let foreign = CADCommand(objectID: UUID(), revision: w.cad.revision, operation: .reset)
        let rejectedOwner = await w.cad.execute(foreign) { true }; precondition(!rejectedOwner)
        for _ in 0..<10 { precondition(w.setMode(.mesh)); precondition(w.mesh.document.positions == meshPositions); precondition(w.setMode(.cad)); precondition(w.cad.bodyID == before) }
        // Bound retained history memory and exercise ownership while evicting old snapshots.
        for _ in 0..<40 { await action(w, .reset) }
        let stats = try await w.cad.service.registryStats(); precondition(stats.0 <= 33 && stats.1 == 0)
        for _ in 0..<32 { await action(w, .undo) }; precondition(!w.cad.canUndo && w.cad.canRedo)
        for _ in 0..<32 { await action(w, .redo) }; precondition(w.cad.canUndo && !w.cad.canRedo)
        await w.cad.service.shutdown()
        let final = try await w.cad.service.registryStats(); precondition(final.0 == 0 && final.1 == 0)
        print("PASS: B-rep Vertex/Edge/Face identity and mode isolation; Box and cut-solid real CAD previews")
        print("PASS: absolute normal projection, stable gesture Entity, multi-step Undo/Redo, redo branching, stale command rejection")
        print("PASS: invalid/cancelled edits rollback, 100 inputs coalesce into one command, 32-entry history bound, zero leaked handles")
    }
}
