// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import SwiftUI
import RealityKit
import Observation
import Foundation
import simd

enum WorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case mesh = "Mesh Mode", cad = "CAD Mode"
    var id: Self { self }
}

enum MeshAction { case undo, redo, reset }

struct MeshInputContext: Equatable {
    let mode: WorkspaceMode
    let activation: UInt64
    let objectID: UUID
    let revision: UInt64
    let selection: Selection
}

/// Coordinates two independent sessions, without converting or resetting their documents.
@MainActor @Observable final class WorkspaceModel {
    static let immersiveID = "SpatialEditor"
    let mesh: EditorViewModel
    let cad: CADSession
    let meshObject: ObjectTransformSession
    let cadObject: ObjectTransformSession
    private(set) var meshObjectMode = false
    private(set) var cadObjectMode = false
    private(set) var meshHistory = WorkspaceHistory(limit: 100)
    private(set) var cadHistory = WorkspaceHistory(limit: 32)
    var activeObject: ObjectTransformSession { activeMode == .mesh ? meshObject : cadObject }
    var isObjectMode: Bool { activeMode == .mesh ? meshObjectMode : cadObjectMode }
    var objectEditing: Bool { meshObject.isEditing || cadObject.isEditing }
    var selectionMode: ModelingSelection {
        if isObjectMode { return .object }
        return ModelingSelection(rawValue: activeMode == .mesh ? mesh.mode.rawValue : cad.selectionMode.rawValue)!
    }
    var canUndo: Bool { canSwitchModes && !(activeMode == .mesh ? meshHistory.undo : cadHistory.undo).isEmpty }
    var canRedo: Bool { canSwitchModes && !(activeMode == .mesh ? meshHistory.redo : cadHistory.redo).isEmpty }

    private(set) var activeMode: WorkspaceMode = .mesh
    private(set) var activation: UInt64 = 0
    private(set) var spaceReady = false
    private(set) var meshInput: MeshInputContext?
    var immersiveState: ImmersiveState = .closed
    private(set) var conversionBusy = false
    private(set) var conversionMS: Double = 0
    private var conversionEpoch: UInt64 = 0
    var errorMessage: String?

    init(recordCADMeasurements: Bool = true) {
        let meshSession = EditorViewModel(), cadSession = CADSession(recordMeasurements: recordCADMeasurements)
        mesh = meshSession; cad = cadSession
        meshObject = ObjectTransformSession(objectID: meshSession.objectID, root: meshSession.renderer.root)
        cadObject = ObjectTransformSession(objectID: cadSession.objectID, root: cadSession.renderer.root)
        meshObject.onCommit = { [weak self] command in self?.meshHistory.record(.transform(command)) }
        cadObject.onCommit = { [weak self] command in self?.cadHistory.record(.transform(command)) }
        cad.onShapeCommit = { [weak self] in self?.cadHistory.record(.shape) }

    }

    var canSwitchModes: Bool {
        !mesh.isDragging && !cad.isEditing && !objectEditing && !conversionBusy && immersiveState != .opening && immersiveState != .closing
    }

    @discardableResult
    func setMode(_ mode: WorkspaceMode) -> Bool {
        guard canSwitchModes else { return false }
        guard mode != activeMode else { return true }
        activeMode = mode
        activation += 1
        synchronizeVisibility()
        return true
    }

    func prepareScene() throws { try mesh.prepareRenderer(); synchronizeVisibility() }

    /// Each root owns its Transform. Mode changes never touch either root's placement.
    /// Opening a new immersive space follows the original app's user-relative placement policy.
    func placeSessions(at transform: Transform) {
        meshObject.place(transform)
        cadObject.place(transform)
        mesh.isPlaced = true
        cad.isPlaced = true
        spaceReady = true
        synchronizeVisibility()
    }

    func synchronizeObjectTargets() {
        mesh.renderer.setObjectMode(meshObjectMode)
        cad.renderer.setObjectMode(cadObjectMode)
        meshObject.syncTarget(points: mesh.document.vertices.map(\.position), active: meshObjectMode && activeMode == .mesh && spaceReady)
        cadObject.syncTarget(points: cad.committedMesh?.vertices.map(\.position) ?? [], active: cadObjectMode && activeMode == .cad && spaceReady)
    }
    func synchronizeVisibility() {
        mesh.renderer.root.isEnabled = spaceReady && activeMode == .mesh
        cad.renderer.root.isEnabled = spaceReady && activeMode == .cad
        synchronizeObjectTargets()
    }

    func setMeshEditMode(_ mode: EditMode) {
        guard activeMode == .mesh, !cad.isEditing, !objectEditing, !conversionBusy else { return }
        meshObjectMode = false; mesh.setMode(mode); synchronizeObjectTargets()
    }

    @discardableResult
    func performMesh(_ action: MeshAction) -> Bool {
        guard activeMode == .mesh, !mesh.isDragging, !cad.isEditing, !objectEditing, !conversionBusy else { return false }
        switch action {
        case .undo:
            guard let entry = meshHistory.undo.last else { return false }
            var moved=entry
            switch entry { case .shape: guard mesh.canUndo else { return false }; mesh.undo()
            case .transform(let command): meshObject.restore(command.before)
            case let .meshConversion(before,_,beforePose,_):
                let current=mesh.document, currentPose=ObjectPose(mesh.renderer.root.transform)
                do { try mesh.replaceDocument(before) } catch { errorMessage=error.localizedDescription;return false }
                meshObject.restore(beforePose)
                moved = .meshConversion(before:before,after:current,beforePose:beforePose,afterPose:currentPose)
            case .cadConversion: return false
            }
            meshHistory.undo.removeLast(); meshHistory.redo.append(moved)
        case .redo:
            guard let entry = meshHistory.redo.last else { return false }
            var moved=entry
            switch entry { case .shape: guard mesh.canRedo else { return false }; mesh.redo()
            case .transform(let command): meshObject.restore(command.after)
            case let .meshConversion(_,after,_,afterPose):
                let current=mesh.document,currentPose=ObjectPose(mesh.renderer.root.transform)
                do { try mesh.replaceDocument(after) } catch { errorMessage=error.localizedDescription;return false }
                meshObject.restore(afterPose)
                moved = .meshConversion(before:current,after:after,beforePose:currentPose,afterPose:afterPose)
            case .cadConversion: return false
            }
            meshHistory.redo.removeLast(); meshHistory.undo.append(moved)
        case .reset:
            let before = mesh.document.positions; mesh.reset()
            if before != mesh.document.positions { meshHistory.record(.shape) }
        }
        synchronizeObjectTargets()
        return true
    }

    func endSpace() {
        conversionEpoch += 1
        cancelMeshInput()
        meshObject.cancel(); cadObject.cancel()
        cad.cancelDrag()
        spaceReady = false
        mesh.isPlaced = false
        cad.isPlaced = false
        synchronizeVisibility()
        mesh.renderer.root.removeFromParent()
        cad.renderer.root.removeFromParent()
        immersiveState = .closed
    }

    @discardableResult
    func beginMeshInput(entity: Entity, at position: SIMD3<Float>, activation expected: UInt64) -> Bool {
        guard activeMode == .mesh, !meshObjectMode, !objectEditing, !conversionBusy, activation == expected, spaceReady, !cad.isEditing,
              meshInput == nil, !mesh.isDragging,
              let selection = SelectionController.target(for: entity, mode: mesh.mode,
                  objectID: mesh.objectID, revision: mesh.revision) else { return false }
        let context = MeshInputContext(mode: .mesh, activation: expected, objectID: mesh.objectID,
                                       revision: mesh.revision, selection: selection)
        mesh.beginDrag(selection, at: position)
        guard mesh.isDragging else { return false }
        meshInput = context
        return true
    }

    private func validMeshInput(_ expected: UInt64) -> Bool {
        guard let input = meshInput else { return false }
        return spaceReady && activeMode == input.mode && input.activation == expected && activation == expected
            && input.objectID == mesh.objectID && input.revision == mesh.revision
            && input.selection == mesh.document.drag?.selection
    }

    func updateMeshInput(to position: SIMD3<Float>, activation expected: UInt64) {
        guard validMeshInput(expected) else { return }
        mesh.updateDrag(to: position)
    }

    func finishMeshInput(at position: SIMD3<Float>, activation expected: UInt64) {
        guard validMeshInput(expected) else { return }
        mesh.updateDrag(to: position)
        let before = mesh.document.drag?.initialPositions
        mesh.finishDrag()
        if let before, before != mesh.document.positions { meshHistory.record(.shape) }
        meshInput = nil
        synchronizeObjectTargets()
    }

    func cancelMeshInput(activation expected: UInt64? = nil) {
        if let expected, let input = meshInput, expected != input.activation { return }
        mesh.cancelDrag()
        meshInput = nil
    }

    @discardableResult
    func performCAD(_ action: CADAction) async -> Bool {
        guard activeMode == .cad, !mesh.isDragging, !cad.isEditing, !objectEditing, !conversionBusy else { return false }
        if action == .undo || action == .redo {
            let entry = action == .undo ? cadHistory.undo.last : cadHistory.redo.last
            guard let entry else { return false }
            let succeeded: Bool
            switch entry {
            case .shape:
                succeeded = await cad.perform(action) { [weak self] in self?.activeMode == .cad }
            case .transform(let command):
                cadObject.restore(action == .undo ? command.before : command.after); succeeded = true
            case let .cadConversion(beforePose,afterPose):
                succeeded=await cad.perform(action) { [weak self] in self?.activeMode == .cad }
                if succeeded { cadObject.restore(action == .undo ? beforePose : afterPose) }
            case .meshConversion: return false
            }
            guard succeeded else { return false }
            if action == .undo { cadHistory.undo.removeLast(); cadHistory.redo.append(entry) }
            else { cadHistory.redo.removeLast(); cadHistory.undo.append(entry) }
            synchronizeVisibility(); return true
        }
        let expectedActivation = activation
        let objectID = cad.objectID
        let succeeded = await cad.perform(action) { [weak self] in
            guard let self else { return false }
            return self.activeMode == .cad && self.activation == expectedActivation && self.cad.objectID == objectID
        }
        synchronizeVisibility()
        return succeeded
    }

    func setCADSelectionMode(_ mode: CADSelectionMode) {
        guard activeMode == .cad, !cad.isEditing, !objectEditing, !conversionBusy else { return }
        cadObjectMode = false; cad.setSelectionMode(mode); synchronizeObjectTargets()
    }
    @discardableResult
    func beginCADInput(entity: Entity, at position: SIMD3<Float>, activation expected: UInt64) -> Bool {
        guard activeMode == .cad, !cadObjectMode, !objectEditing, !conversionBusy, activation == expected, spaceReady, !mesh.isDragging else { return false }
        return cad.beginDrag(entity, at: position) { [weak self] in
            guard let self else { return false }
            return self.activeMode == .cad && self.activation == expected && self.spaceReady
        }
    }
    func updateCADInput(to position: SIMD3<Float>, activation expected: UInt64, entity: Entity? = nil) {
        guard activeMode == .cad, activation == expected, spaceReady else { return }
        if let entity, !cad.matchesDragTarget(entity) { return }
        cad.updateDrag(to: position)
    }
    func finishCADInput(at position: SIMD3<Float>, activation expected: UInt64, entity: Entity? = nil) {
        guard activeMode == .cad, activation == expected, spaceReady else { return }
        if let entity, !cad.matchesDragTarget(entity) { return }
        cad.finishDrag(at: position)
    }

    @discardableResult
    func selectCAD(_ entity: Entity, activation expected: UInt64) -> Bool {
        guard activeMode == .cad, !cadObjectMode, !objectEditing, !conversionBusy, activation == expected, spaceReady, !cad.isEditing else { return false }
        return cad.select(entity)
    }
}

@MainActor extension WorkspaceModel {
    func setSelectionMode(_ mode: ModelingSelection) {
        guard canSwitchModes else { return }
        if mode == .object {
            if activeMode == .mesh { meshObjectMode = true } else { cadObjectMode = true }
            synchronizeObjectTargets()
        } else if activeMode == .mesh { setMeshEditMode(EditMode(rawValue: mode.rawValue)!) }
        else { setCADSelectionMode(CADSelectionMode(rawValue: mode.rawValue)!) }
    }
    var objectCenter: SIMD3<Float> {
        let points = activeMode == .mesh ? mesh.document.vertices.map(\.position) : cad.committedMesh?.vertices.map(\.position) ?? []
        guard let first = points.first else { return .zero }
        return (points.reduce(first) { simd_min($0,$1) } + points.reduce(first) { simd_max($0,$1) }) / 2
    }
    @discardableResult func beginObject(entity: Entity? = nil, source: ObjectTransformSession.Source, activation expected: UInt64) -> Bool {
        guard canSwitchModes, isObjectMode, spaceReady, activation == expected else { return false }
        if let entity {
            guard entity.isEnabledInHierarchy, let target = entity.components[ObjectTarget.self],
                  target.objectID == activeObject.objectID, target.revision == activeObject.revision else { return false }
        }
        return activeObject.begin(center: objectCenter, source: source)
    }
    func updateObject(translation: SIMD3<Float>? = nil, magnification: Float? = nil, rotation: simd_quatf? = nil, activation expected: UInt64) {
        guard isObjectMode, spaceReady, activation == expected, activeObject.source == .gesture else { return }
        activeObject.previewGesture(translation: translation, magnification: magnification, rotation: rotation)
    }
    func finishObject(activation expected: UInt64) {
        guard activation == expected, activeObject.source == .gesture else { return }
        activeObject.finish(); synchronizeObjectTargets()
    }
    func cancelObject() { meshObject.cancel(); cadObject.cancel() }
    @discardableResult func setDisplayPercent(_ percent: Double, commit: Bool) -> Bool {
        guard percent.isFinite, (1...1000).contains(percent) else { activeObject.errorMessage = "Enter a finite scale from 1% to 1000%."; return false }
        if !activeObject.isEditing {
            guard beginObject(source: .slider, activation: activation) else { return false }
        }
        guard activeObject.source == .slider else { return false }
        let valid = activeObject.previewPercent(percent)
        if commit { activeObject.finish(); synchronizeObjectTargets() }
        return valid
    }
    func finishScaleSlider() { guard activeObject.source == .slider else { return }; activeObject.finish(); synchronizeObjectTargets() }
    func resetObjectTransform() { guard canSwitchModes, isObjectMode else { return }; _ = activeObject.reset(); synchronizeObjectTargets() }
}

@MainActor extension WorkspaceModel {
    func conversionNeedsConfirmation(to target: WorkspaceMode) -> Bool {
        target == .mesh || cad.hasBody
    }
    @discardableResult func convert(to target: WorkspaceMode, replaceConfirmed: Bool) async -> Bool {
        guard canSwitchModes, spaceReady, target != activeMode else { return false }
        guard !conversionNeedsConfirmation(to:target) || replaceConfirmed else {
            errorMessage="Confirm replacement of the destination session first.";return false
        }
        conversionBusy=true;errorMessage=nil;conversionEpoch+=1
        let epoch=conversionEpoch, generation=activation, sourceRevision=activeMode == .mesh ? mesh.revision : cad.revision
        let sourcePose=ObjectPose(activeMode == .mesh ? mesh.renderer.root.transform : cad.renderer.root.transform)
        let sourceMode=activeMode
        let authorized: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            let revision=self.activeMode == .mesh ? self.mesh.revision : self.cad.revision
            let pose=ObjectPose(self.activeMode == .mesh ? self.mesh.renderer.root.transform : self.cad.renderer.root.transform)
            return self.conversionEpoch==epoch && self.activation==generation && self.activeMode==sourceMode
                && revision==sourceRevision && pose==sourcePose && self.spaceReady
        }
        let start=DispatchTime.now().uptimeNanoseconds
        defer { conversionBusy=false;conversionMS=milliseconds(DispatchTime.now().uptimeNanoseconds-start) }
        do {
            if target == .cad {
                let input=try CADPolygonMesh.from(mesh.document)
                if !cad.hasBody {
                    guard await cad.perform(.generate,isCurrent:authorized) else { throw CADIntegrationError(message:cad.errorMessage ?? "CAD initialization failed.") }
                }
                let oldPose=ObjectPose(cad.renderer.root.transform)
                guard await cad.execute(cad.command(.replaceMesh(input)),isCurrent:authorized) else {
                    throw CADIntegrationError(message:cad.errorMessage ?? "Mesh to CAD failed.")
                }
                cadObject.restore(sourcePose)
                if !cadHistory.undo.isEmpty { cadHistory.undo[cadHistory.undo.count-1] = .cadConversion(beforePose:oldPose,afterPose:sourcePose) }
            } else {
                guard let polygons=cad.committedMesh?.polygonMesh else { throw CADIntegrationError(message:"CAD to Mesh supports one planar/straight-edge shell with simple face loops.") }
                let next=try polygons.document()
                await Task.yield()
                guard authorized(), !Task.isCancelled else { throw CADIntegrationError(message:"Conversion cancelled; source and destination retained.") }
                let previous=mesh.document,oldPose=ObjectPose(mesh.renderer.root.transform)
                try mesh.replaceDocument(next)
                meshObject.restore(sourcePose)
                meshHistory.record(.meshConversion(before:previous,after:next,beforePose:oldPose,afterPose:sourcePose))
            }
            activeMode=target;activation+=1;synchronizeVisibility();return true
        } catch { errorMessage=error.localizedDescription;return false }
    }
}
