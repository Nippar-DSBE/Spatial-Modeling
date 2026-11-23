// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import RealityKit
import simd
import SolidCoreProbe

@main struct ModeIntegrationChecks {
    @MainActor static func descendants(_ entity: Entity) -> [Entity] {
        [entity] + entity.children.flatMap { descendants($0) }
    }
    @MainActor static func meshHandle(_ workspace: WorkspaceModel, mode: EditMode, id: Int) -> Entity {
        descendants(workspace.mesh.renderer.root).first {
            $0.components[EditTargetComponent.self]?.selection == Selection(mode: mode, id: id)
        }!
    }
    @MainActor static func cadHandle(_ workspace: WorkspaceModel) -> Entity {
        descendants(workspace.cad.renderer.root).first { $0.components[CADFaceTarget.self] != nil }!
    }
    static func volume(_ id: UInt64) -> Double {
        var value = 0.0
        precondition(sc_body_volume(id, &value) == 0, "CAD volume query failed")
        return value
    }

    @MainActor static func main() async throws {
        EditTargetComponent.registerComponent()
        CADFaceTarget.registerComponent()
        CADTopologyTarget.registerComponent()
        let workspace = WorkspaceModel(recordCADMeasurements: false)
        try workspace.prepareScene()
        let sharedSpace = Entity()
        sharedSpace.addChild(workspace.mesh.renderer.root)
        sharedSpace.addChild(workspace.cad.renderer.root)
        workspace.immersiveState = .open
        workspace.placeSessions(at: Transform(translation: [0, 1.2, -0.9]))
        precondition(workspace.mesh.renderer.root.isEnabled && !workspace.cad.renderer.root.isEnabled)
        let initial = workspace.mesh.document.positions
        var snapshots: [PositionSnapshot] = []
        for mode in EditMode.allCases {
            workspace.setMeshEditMode(mode)
            let handle = meshHandle(workspace, mode: mode, id: 0)
            let generation = workspace.activation
            precondition(workspace.beginMeshInput(entity: handle, at: .zero, activation: generation))
            precondition(!workspace.canSwitchModes && !workspace.setMode(.cad), "No mode change while dragging")
            workspace.updateMeshInput(to: [0.025, 0.015, -0.02], activation: generation)
            workspace.finishMeshInput(at: [0.025, 0.015, -0.02], activation: generation)
            snapshots.append(workspace.mesh.document.positions)
        }
        let meshSelection = workspace.mesh.document.selection
        let meshUndo = workspace.mesh.document.history.undoStack
        let meshRevision = workspace.mesh.revision
        workspace.mesh.renderer.root.position.x = -0.23
        workspace.cad.renderer.root.position.x = 0.24
        workspace.cad.renderer.root.orientation = simd_quatf(angle: 0.3, axis: [0,1,0])
        let meshPosition = workspace.mesh.renderer.root.position
        let cadPosition = workspace.cad.renderer.root.position
        let cadRotation = workspace.cad.renderer.root.orientation.vector
        let firstMeshActivation = workspace.activation
        precondition(workspace.setMode(.cad))
        precondition(!workspace.mesh.renderer.root.isEnabled && workspace.cad.renderer.root.isEnabled)
        precondition(descendants(workspace.mesh.renderer.root).filter { $0.components[EditTargetComponent.self] != nil }.allSatisfy { !$0.isEnabledInHierarchy })
        precondition(!workspace.performMesh(.reset), "Inactive Mesh UI commands rejected")
        let generated = await workspace.performCAD(.generate)
        precondition(generated && workspace.cad.measurements?.faces == 6)
        precondition(abs(volume(workspace.cad.bodyID) - 27_000_000) < 1)
        let cadBoxID = workspace.cad.bodyID
        let cadBoxRevision = workspace.cad.revision
        let firstCADActivation = workspace.activation
        let oldFace = cadHandle(workspace)
        precondition(workspace.selectCAD(oldFace, activation: firstCADActivation))
        let selectedCADFace = workspace.cad.selectedFace
        precondition(workspace.mesh.document.positions == snapshots[2] && workspace.mesh.document.history.undoStack == meshUndo)

        precondition(workspace.setMode(.mesh))
        precondition(!workspace.selectCAD(oldFace, activation: firstCADActivation))
        precondition(workspace.mesh.mode == .face && workspace.mesh.document.selection == meshSelection)
        precondition(workspace.mesh.revision == meshRevision && workspace.mesh.document.history.undoStack == meshUndo)
        precondition(workspace.performMesh(.undo) && workspace.mesh.document.positions == snapshots[1])
        precondition(workspace.performMesh(.redo) && workspace.mesh.document.positions == snapshots[2])
        precondition(workspace.performMesh(.reset) && workspace.mesh.document.positions == initial)
        precondition(workspace.performMesh(.undo) && workspace.mesh.document.positions == snapshots[2])
        let inactiveCADAction = await workspace.performCAD(.cut)
        precondition(!inactiveCADAction && workspace.cad.bodyID == cadBoxID && workspace.cad.revision == cadBoxRevision)
        let validMeshHandle = meshHandle(workspace, mode: .face, id: 0)
        precondition(!workspace.beginMeshInput(entity: validMeshHandle, at: .zero, activation: firstMeshActivation), "Stale activation rejected")
        let fake = Entity()
        workspace.mesh.renderer.root.addChild(fake)
        fake.components.set(EditTargetComponent(selection: Selection(mode: .face, id: 0), objectID: UUID(), revision: workspace.mesh.revision))
        precondition(!workspace.beginMeshInput(entity: fake, at: .zero, activation: workspace.activation), "Foreign object rejected")
        fake.components.set(EditTargetComponent(selection: Selection(mode: .face, id: 0), objectID: workspace.mesh.objectID, revision: workspace.mesh.revision - 1))
        precondition(!workspace.beginMeshInput(entity: fake, at: .zero, activation: workspace.activation), "Stale geometry revision rejected")
        fake.removeFromParent()
        let beforeCancel = workspace.mesh.document.positions
        precondition(workspace.beginMeshInput(entity: validMeshHandle, at: .zero, activation: workspace.activation))
        workspace.updateMeshInput(to: [0.2,0.1,0.1], activation: workspace.activation)
        workspace.cancelMeshInput()
        precondition(workspace.mesh.document.positions == beforeCancel)
        let stableMesh = workspace.mesh.document.positions
        let stableHistory = workspace.mesh.document.history.undoStack

        precondition(workspace.setMode(.cad))
        precondition(workspace.cad.selectedFace == selectedCADFace && workspace.cad.bodyID == cadBoxID)
        precondition(!workspace.selectCAD(oldFace, activation: firstCADActivation), "Old gesture cannot select after returning to CAD")
        precondition(workspace.selectCAD(oldFace, activation: workspace.activation))
        let cut = await workspace.performCAD(.cut)
        precondition(cut && workspace.cad.measurements?.faces == 9)
        precondition(abs(volume(workspace.cad.bodyID) - 23_625_000) < 1)
        precondition(!workspace.selectCAD(oldFace, activation: workspace.activation), "Old Body/face entity rejected after Boolean")
        let cutBody = workspace.cad.bodyID
        let cutRevision = workspace.cad.revision
        let newFace = cadHandle(workspace)
        precondition(workspace.selectCAD(newFace, activation: workspace.activation))
        let cutSelection = workspace.cad.selectedFace
        for _ in 0..<20 {
            precondition(workspace.setMode(.mesh))
            precondition(workspace.mesh.document.positions == stableMesh && workspace.mesh.document.history.undoStack == stableHistory)
            precondition(!workspace.selectCAD(newFace, activation: workspace.activation))
            precondition(workspace.setMode(.cad))
            precondition(workspace.cad.bodyID == cutBody && workspace.cad.revision == cutRevision && workspace.cad.canUndo)
            precondition(workspace.cad.selectedFace == cutSelection)
            precondition(workspace.mesh.renderer.root.position == meshPosition)
            precondition(workspace.cad.renderer.root.position == cadPosition && workspace.cad.renderer.root.orientation.vector == cadRotation)
            precondition(workspace.mesh.renderer.root.parent === sharedSpace && workspace.cad.renderer.root.parent === sharedSpace)
            precondition(workspace.immersiveState == .open && workspace.spaceReady)
        }
        let undoCAD = await workspace.performCAD(.undo)
        precondition(undoCAD && abs(volume(workspace.cad.bodyID) - 27_000_000) < 1)
        precondition(workspace.mesh.document.positions == stableMesh && workspace.mesh.document.history.undoStack == stableHistory)

        // Invalidate the asynchronous result between prepare and commit; the old CAD state must survive.
        let beforeRejectedBody = workspace.cad.bodyID
        let beforeRejectedRevision = workspace.cad.revision
        var busyGuardChecked = false
        let rejected = await workspace.cad.perform(.reset) {
            if workspace.cad.busy {
                busyGuardChecked = true
                precondition(!workspace.canSwitchModes && !workspace.setMode(.mesh))
                return false
            }
            return true
        }
        precondition(!rejected && busyGuardChecked && workspace.cad.bodyID == beforeRejectedBody && workspace.cad.revision == beforeRejectedRevision)
        precondition(abs(volume(workspace.cad.bodyID) - 27_000_000) < 1)
        let reset = await workspace.performCAD(.reset)
        precondition(reset && workspace.cad.measurements?.faces == 6)
        workspace.endSpace()
        precondition(!workspace.mesh.renderer.root.isEnabled && !workspace.cad.renderer.root.isEnabled)
        precondition(workspace.mesh.document.positions == stableMesh && workspace.cad.hasBody)
        let (bodies, meshes, bytes) = try await workspace.cad.service.registryStats()
        precondition(bodies <= 33 && meshes == 0 && bytes == 0)
        await workspace.cad.service.shutdown()
        let final = try await workspace.cad.service.registryStats()
        precondition(final.0 == 0 && final.1 == 0)
        print("PASS: Vertex/Edge/Face edits, Mesh Undo/Redo/Reset, real CAD Box/Cut/Undo/Reset")
        print("PASS: 20 mode round trips preserve geometry, histories, selection, root transforms and the same shared space")
        print("PASS: inactive inputs/actions, stale mode/object/revision, busy switching, rejected async commit, cancellation and handle cleanup")
    }
}
