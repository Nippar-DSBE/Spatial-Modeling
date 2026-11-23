// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import SwiftUI
import Observation
import RealityKit
import Foundation
import simd

@MainActor @Observable final class CADSession {
    let objectID = UUID()
    @ObservationIgnored let service = CADService()
    @ObservationIgnored let renderer = CADRenderer()
    @ObservationIgnored var onShapeCommit: (() -> Void)?
    @ObservationIgnored private let recordMeasurements: Bool
    private(set) var busy = false
    private(set) var isDragging = false
    var isEditing: Bool { busy || isDragging }
    private(set) var hasBody = false
    private(set) var hasCut = false
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var selectionMode: CADSelectionMode = .face
    private(set) var selection: CADSelection?
    var selectedFace: UInt32? { selection?.mode == .face ? selection?.id : nil }
    private(set) var measurements: CADMeasurements?
    private(set) var revision: UInt64 = 0
    private(set) var bodyID: UInt64 = 0
    private(set) var distanceMM: Double = 0
    private(set) var previewValid = true
    private(set) var reconstructing = false
    private(set) var hybridPreviewMS: Double = 0
    private(set) var hybridMeshUpdateMS: Double = 0
    private(set) var directDisplacementMM = SIMD3<Double>.zero
    @ObservationIgnored private(set) var committedMesh: CADMesh?
    @ObservationIgnored private var drag: Drag?
    @ObservationIgnored private var pump: Task<Void, Never>?
    var dragLabelPosition: SIMD3<Float> {
        guard let drag else { return .zero }
        let offset=drag.hybrid == nil ? CADCoordinateConversion.offsetMeters(distanceMM, along:drag.element.normal) : drag.delta
        return drag.element.position + offset + SIMD3<Float>(0, 0.035, 0)
    }
    var errorMessage: String?
    var isPlaced = false

    @MainActor private final class Drag {
        let start: SIMD3<Float>
        let element: CADTopologyElement
        let revision: UInt64
        let authorized: @MainActor () -> Bool
        var requested: Double = 0
        var sequence: UInt64 = 0
        var processed: UInt64 = 0
        var ending = false
        var cancelled = false
        var hybrid: CADHybridEdit?
        var delta = SIMD3<Float>.zero
        var prepared: PreparedCAD?
        init(start: SIMD3<Float>, element: CADTopologyElement, revision: UInt64, authorized: @escaping @MainActor () -> Bool) {
            self.start = start; self.element = element; self.revision = revision; self.authorized = authorized
        }
    }
    init(recordMeasurements: Bool = true) { self.recordMeasurements = recordMeasurements }

    func setSelectionMode(_ mode: CADSelectionMode) {
        guard !isEditing else { return }
        selectionMode = mode; selection = nil; renderer.setMode(mode)
    }
    func command(_ operation: CADOperation) -> CADCommand {
        CADCommand(objectID: objectID, revision: revision, operation: operation)
    }
    @discardableResult
    func perform(_ action: CADAction, isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        let operation: CADOperation
        switch action { case .generate: operation = .generate; case .cut: operation = .cut
        case .undo: operation = .undo; case .redo: operation = .redo; case .reset: operation = .reset }
        return await execute(command(operation), isCurrent: isCurrent)
    }
    @discardableResult
    func execute(_ command: CADCommand, isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        guard !isEditing, isCurrent(), command.objectID == objectID, command.expectedRevision == revision, command.version == 1 else { return false }
        busy = true; errorMessage = nil
        let expectedRevision = revision
        var token: UInt64?
        defer { busy = false }
        do {
            let prepared = try await service.prepare(command)
            token = prepared.token
            guard isCurrent(), revision == expectedRevision, !Task.isCancelled else { throw CADIntegrationError(message: "操作をキャンセルしました。") }
            let start = DispatchTime.now().uptimeNanoseconds
            let staged = try renderer.stage(prepared.mesh, objectID: objectID)
            let preparationMS = milliseconds(DispatchTime.now().uptimeNanoseconds - start)
            guard isCurrent(), revision == expectedRevision, !Task.isCancelled else { throw CADIntegrationError(message: "操作をキャンセルしました。") }
            let committed = try await service.commit(prepared.token)
            token = nil
            renderer.install(staged)
            apply(prepared, committed: committed)
            switch command.operation { case .undo, .redo: break; default: if committed.canUndo { onShapeCommit?() } }
            await measure(prepared.measurements, updateMS: staged.meshUpdateMS, preparationMS: preparationMS)
            return true
        } catch {
            if let token { await service.abort(token) }
            errorMessage = error.localizedDescription
            return false
        }
    }
    private func apply(_ prepared: PreparedCAD, committed: CommittedCAD) {
        hasBody = true; canUndo = committed.canUndo; canRedo = committed.canRedo; hasCut = committed.wasCut
        revision = prepared.mesh.revision; bodyID = prepared.mesh.body; committedMesh = prepared.mesh
        selection = nil
    }
    private func measure(_ value: CADMeasurements, updateMS: Double, preparationMS: Double = 0, preview: Bool = false) async {
        var measured = value
        measured.swiftPreviewMS=hybridPreviewMS
        if preview { measured.operation = "PushPullPreview" }
        measured.lowLevelMeshMS = updateMS; measured.renderPreparationMS = preparationMS
        if let (bodies, meshes, _) = try? await service.registryStats() { measured.liveBodies = bodies; measured.liveMeshes = meshes }
        measured.footprintBytes = cad_memory_bytes(); measurements = measured
        if recordMeasurements { await service.record(measured) }
    }
    @discardableResult
    func select(_ entity: Entity) -> Bool {
        guard !isEditing, renderer.root.isEnabledInHierarchy, entity.isEnabledInHierarchy,
              let target = entity.components[CADTopologyTarget.self], target.objectID == objectID,
              target.body == bodyID, target.revision == revision, target.selection.mode == selectionMode,
              committedMesh?.topology.contains(where: { $0.selection == target.selection }) == true,
              renderer.select(target) else { return false }
        selection = target.selection
        return true
    }
    @discardableResult
    func beginDrag(_ entity: Entity, at start: SIMD3<Float>, isCurrent: @escaping @MainActor () -> Bool) -> Bool {
        guard isCurrent(), select(entity), let selection,
              let element=committedMesh?.topology.first(where:{ $0.selection==selection }), element.editable else { return false }
        let next=Drag(start:start,element:element,revision:revision,authorized:isCurrent)
        if selection.mode != .face {
            guard let mesh=committedMesh?.polygonMesh else { errorMessage="Hybrid editing requires planar polygon boundaries.";return false }
            do { next.hybrid=try CADHybridEdit(mesh,selection:Selection(mode:EditMode(rawValue:selection.mode.rawValue)!,id:Int(selection.id)),start:start) }
            catch { errorMessage=error.localizedDescription;return false }
        } else if simd_length_squared(element.normal)<0.99 { return false }
        drag=next;directDisplacementMM = .zero
        isDragging = true; distanceMM = 0; previewValid = true; errorMessage = nil
        renderer.beginPreview(selection)
        return true
    }
    func matchesDragTarget(_ entity: Entity) -> Bool {
        guard let drag, let target = entity.components[CADTopologyTarget.self] else { return false }
        return target.objectID == objectID && target.body == bodyID && target.revision == drag.revision
            && target.selection == drag.element.selection
    }
    func updateDrag(to position: SIMD3<Float>) {
        guard let drag, !drag.ending, !drag.cancelled else { return }
        request(position, drag: drag)
    }
    private func request(_ position: SIMD3<Float>, drag: Drag) {
        if drag.hybrid != nil {
            guard position.allFinite, let snapshot=committedMesh else { return }
            let start=DispatchTime.now().uptimeNanoseconds
            drag.delta=position-drag.start
            directDisplacementMM=CADCoordinateConversion.cadPositionMM(drag.delta)
            distanceMM=Double(simd_length(drag.delta))*1000
            drag.requested=distanceMM
            drag.hybrid?.document.updateDrag(to:position)
            do {
                let display=drag.hybrid!.display(snapshot:snapshot)
                hybridMeshUpdateMS=try renderer.previewHybrid(display,selected:drag.element,delta:drag.delta)
                hybridPreviewMS=milliseconds(DispatchTime.now().uptimeNanoseconds-start)
                previewValid=true;errorMessage=nil
            } catch { previewValid=false;errorMessage=error.localizedDescription }
            return
        }
        let distance = CADCoordinateConversion.distanceMM(position - drag.start, along: drag.element.normal)
        guard distance.isFinite else { return }
        // Absolute displacement from the immutable starting body; no frame-wise accumulation.
        if abs(distance - drag.requested) >= 0.1 { drag.requested = distance; drag.sequence += 1 }
        distanceMM = distance
        startPump()
    }
    func finishDrag(at position: SIMD3<Float>) {
        guard let drag, !drag.cancelled, !drag.ending else { return }
        request(position, drag: drag)
        drag.ending = true
        reconstructing = drag.hybrid != nil
        startPump()
    }
    func cancelDrag(unlessEnding: Bool = false) {
        guard let drag, !(unlessEnding && drag.ending) else { return }
        drag.cancelled = true
        startPump()
    }
    // At most one CAD operation in flight. New input replaces a single latest request.
    // 30 Hz ceiling avoids wasting work faster than a visible preview can be delivered.
    private func startPump() {
        guard pump == nil, drag != nil else { return }
        pump = Task { await drain() }
    }
    private func drain() async {
        guard let state = drag else { pump = nil; return }
        defer { pump = nil }
        if state.hybrid != nil { await commitHybrid(state);return }
        while true {
            if state.cancelled || !state.authorized() || revision != state.revision {
                await rollback(state); return
            }
            if state.sequence != state.processed {
                let iterationStart = DispatchTime.now().uptimeNanoseconds
                if let previous = state.prepared { await service.abort(previous.token); state.prepared = nil }
                let sequence = state.sequence
                let distance = state.requested
                state.processed = sequence
                if abs(distance) < 0.1 {
                    renderer.restorePreview(selection: selection); renderer.beginPreview(state.element.selection)
                    previewValid = true
                } else {
                    var token: UInt64?
                    do {
                        let prepared = try await service.prepare(command(.offsetFace(face: state.element.selection.id, distanceMM: distance)))
                        token = prepared.token
                        guard !state.cancelled, state.authorized(), state.revision == revision,
                              state.sequence == sequence else {
                            await service.abort(prepared.token); continue
                        }
                        let updateMS = try renderer.preview(prepared.mesh, selected: state.element, distanceMM: distance)
                        state.prepared = prepared; token = nil; previewValid = true; errorMessage = nil
                        await measure(prepared.measurements, updateMS: updateMS, preview: true)
                    } catch {
                        if let token { await service.abort(token) }
                        previewValid = false; errorMessage = error.localizedDescription
                        // Never show a rejected result or leave it as the final CAD document.
                        renderer.restorePreview(selection: selection); renderer.beginPreview(state.element.selection)
                    }
                }
                if !state.ending {
                    let elapsed = DispatchTime.now().uptimeNanoseconds - iterationStart
                    if elapsed < 33_333_333 { try? await Task.sleep(nanoseconds: 33_333_333 - elapsed) }
                }
                continue
            }
            if state.ending {
                guard previewValid, abs(state.requested) >= 0.1, let prepared = state.prepared else {
                    await rollback(state); return
                }
                do {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let staged = try renderer.stage(prepared.mesh, objectID: objectID)
                    let preparationMS = milliseconds(DispatchTime.now().uptimeNanoseconds - start)
                    guard !state.cancelled, state.authorized() else { await rollback(state); return }
                    // From here commit completes atomically on CADService. Mode switching stays locked.
                    let committed = try await service.commit(prepared.token)
                    state.prepared = nil
                    renderer.install(staged); apply(prepared, committed: committed); onShapeCommit?()
                    drag = nil
                    await measure(prepared.measurements, updateMS: staged.meshUpdateMS, preparationMS: preparationMS)
                    isDragging = false
                } catch { errorMessage = error.localizedDescription; await rollback(state) }
                return
            }
            // No work is queued. A later input event restarts the pump.
            return
        }
    }
    private func commitHybrid(_ state: Drag) async {
        guard !state.cancelled, state.authorized(), state.revision==revision,
              state.ending, state.requested>=0.1, previewValid, let hybrid=state.hybrid else {
            await rollback(state);return
        }
        do {
            let prepared=try await service.prepare(command(.replaceMesh(hybrid.result())))
            state.prepared=prepared
            guard !state.cancelled, state.authorized(), state.revision==revision else { await rollback(state);return }
            let start=DispatchTime.now().uptimeNanoseconds
            let staged=try renderer.stage(prepared.mesh,objectID:objectID)
            let renderMS=milliseconds(DispatchTime.now().uptimeNanoseconds-start)
            guard !state.cancelled, state.authorized() else { await rollback(state);return }
            let committed=try await service.commit(prepared.token)
            state.prepared=nil
            renderer.install(staged);apply(prepared,committed:committed);onShapeCommit?()
            drag=nil
            await measure(prepared.measurements,updateMS:staged.meshUpdateMS,preparationMS:renderMS)
            isDragging=false;reconstructing=false
        } catch { errorMessage=error.localizedDescription;await rollback(state) }
    }
    private func rollback(_ state: Drag) async {
        if let prepared = state.prepared { await service.abort(prepared.token); state.prepared = nil }
        renderer.restorePreview(selection: selection)
        drag = nil; isDragging = false;reconstructing=false
    }
    /// Await pending work in host tests and lifecycle cleanup without polling the CAD actor.
    func waitForPreview() async { while let task = pump { await task.value } }
}
