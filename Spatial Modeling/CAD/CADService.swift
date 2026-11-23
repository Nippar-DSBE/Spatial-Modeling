// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import SolidCoreProbe

struct CADIntegrationError: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

func checkCAD(_ status: Int32) throws {
    guard status != 0 else { return }
    var bytes = [CChar](repeating: 0, count: 4096)
    _ = sc_error_copy(&bytes, bytes.count)
    throw CADIntegrationError(message: String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
}

func milliseconds(_ ns: UInt64) -> Double { Double(ns) / 1_000_000 }

struct CADMesh: Sendable {
    let body: UInt64
    let revision: UInt64
    let vertices: [CADRenderVertex]
    let indices: [UInt32]
    let triangleFaces: [UInt32]
    let topology: [CADTopologyElement]
    let faceCount: Int
    let polygonMesh: CADPolygonMesh?
}

struct CADMeasurements: Sendable {
    var operation: String
    var boxMS: Double = 0
    var booleanMS: Double = 0
    var directModelMS: Double = 0
    var conversionMS: Double = 0
    var splitFaces = 0
    var swiftPreviewMS: Double = 0
    var tessellationMS: Double = 0
    var transferMS: Double = 0
    var lowLevelMeshMS: Double = 0
    var renderPreparationMS: Double = 0
    var vertices = 0
    var triangles = 0
    var faces = 0
    var rustMeshBytes: UInt64 = 0
    var footprintBytes: UInt64 = 0
    var liveBodies: UInt64 = 0
    var liveMeshes: UInt64 = 0
}

enum CADAction: String, Sendable { case generate = "Generate Box", cut = "Boolean Cut", undo = "Undo", redo = "Redo", reset = "Reset" }
struct PreparedCAD: Sendable {
    let token: UInt64
    let mesh: CADMesh
    let wasCut: Bool
    var measurements: CADMeasurements
}
struct CommittedCAD: Sendable { let canUndo: Bool; let canRedo: Bool; let wasCut: Bool }

/// Blocking FFI calls run on this actor's executor, never on MainActor.
/// Rust dispatches CAD work to its own 8 MiB worker; no cooperative-thread stack is used by the kernel.
actor CADService {
    private struct State { let body: UInt64; let wasCut: Bool }
    private var current: UInt64 = 0
    private var currentWasCut = false
    private var undoStack: [State] = []
    private var redoStack: [State] = []
    private var currentRevision: UInt64 = 0
    private var owner: UUID?
    private var nextRevision: UInt64 = 0
    private var pending: (token: UInt64, body: UInt64, owned: Bool, wasCut: Bool, operation: CADOperation)?
    private let historyLimit = 32

    private func box(origin: SIMD3<Double>, size: Double = 300) throws -> (UInt64, Double) {
        var body: UInt64 = 0
        var ns: UInt64 = 0
        try checkCAD(sc_box(origin.x, origin.y, origin.z, size, size, size, &body, &ns))
        return (body, milliseconds(ns))
    }

    func prepare(_ command: CADCommand) throws -> PreparedCAD {
        guard command.version == 1, command.expectedRevision == currentRevision,
              owner == nil || owner == command.objectID else { throw CADIntegrationError(message: "古いCADコマンドを拒否しました。") }
        if owner == nil { owner = command.objectID }
        guard pending == nil else { throw CADIntegrationError(message: "別の操作を確定中です。") }
        var candidate: UInt64 = 0
        var owned = true
        var transferred = false
        var wasCut = false
        let operationName: String
        if case .replaceMesh = command.operation { operationName = "MeshToCAD" } else { operationName = String(describing: command.operation) }
        var measurements = CADMeasurements(operation: operationName)
        defer { if owned && !transferred && candidate != 0 { _ = sc_body_release(candidate) } }
        switch command.operation {
        case .generate, .reset:
            (candidate, measurements.boxMS) = try box(origin: [-150, -150, -150])
        case .cut:
            guard current != 0, !currentWasCut else { throw CADIntegrationError(message: "Boxを生成またはResetしてからCutしてください。") }
            let (tool, time) = try box(origin: [0, -200, 0], size: 200)
            measurements.boxMS = time
            defer { _ = sc_body_release(tool) }
            var ns: UInt64 = 0
            try checkCAD(sc_difference(current, tool, &candidate, &ns))
            measurements.booleanMS = milliseconds(ns)
            wasCut = true
        case .undo, .redo:
            let state: State?
            if case .undo = command.operation { state = undoStack.last } else { state = redoStack.last }
            guard let state else { throw CADIntegrationError(message: "履歴がありません。") }
            candidate = state.body; wasCut = state.wasCut; owned = false
        case let .replaceMesh(input):
            let result=try input.createBody()
            candidate=result.body;measurements.conversionMS=result.milliseconds;measurements.splitFaces=result.splitFaces
            wasCut=false
        case let .offsetFace(face, distanceMM):
            guard current != 0 else { throw CADIntegrationError(message: "CAD形状がありません。") }
            var ns: UInt64 = 0
            try checkCAD(sc_offset_face(current, face, distanceMM, &candidate, &ns))
            measurements.directModelMS = milliseconds(ns)
            wasCut = currentWasCut
        }
        if case .offsetFace = command.operation { /* Already validated inside sc_offset_face. */ }
        else { try checkCAD(sc_body_validate(candidate)) }
        var meshHandle: UInt64 = 0
        try checkCAD(sc_tessellate(candidate, 0.5, &meshHandle))
        defer { _ = sc_mesh_release(meshHandle) }
        var info = SCMeshInfo()
        try checkCAD(sc_mesh_info(meshHandle, &info))
        guard info.body_handle == candidate, info.vertex_count > 0, info.vertex_count <= 1_000_000,
              info.triangle_count > 0, info.triangle_count <= 1_000_000, info.face_count > 0, info.face_count <= 512 else {
            throw CADIntegrationError(message: "CADメッシュの件数またはBodyが不正です。")
        }
        measurements.tessellationMS = milliseconds(info.tessellation_ns)
        let start = DispatchTime.now().uptimeNanoseconds
        var raw = [SCVertex](repeating: SCVertex(), count: Int(info.vertex_count))
        var indices = [UInt32](repeating: 0, count: Int(info.triangle_count) * 3)
        var faces = [UInt32](repeating: 0, count: Int(info.triangle_count))
        try checkCAD(sc_mesh_copy(meshHandle, &raw, raw.count, &indices, indices.count, &faces, faces.count))
        guard info.topology_count > 0, info.topology_count <= 100_000 else { throw CADIntegrationError(message: "B-rep要素数が不正です。") }
        var rawTopology = [SCTopology](repeating: SCTopology(), count: Int(info.topology_count))
        try checkCAD(sc_mesh_topology_copy(meshHandle, &rawTopology, rawTopology.count))
        let topology = try rawTopology.map { item -> CADTopologyElement in
            guard item.kind <= 2, [item.x,item.y,item.z,item.nx,item.ny,item.nz].allSatisfy(\.isFinite) else {
                throw CADIntegrationError(message: "B-rep要素が不正です。")
            }
            let mode: CADSelectionMode = item.kind == 0 ? .vertex : item.kind == 1 ? .edge : .face
            return CADTopologyElement(selection: CADSelection(mode: mode, id: item.id),
                position: CADCoordinateConversion.positionMM([item.x,item.y,item.z]),
                normal: CADCoordinateConversion.normal([item.nx,item.ny,item.nz]), editable: item.editable != 0)
        }
        let polygonMesh = try? CADPolygonMesh.read(meshHandle)
        let vertices = raw.map(CADCoordinateConversion.vertex)
        guard indices.allSatisfy({ Int($0) < vertices.count }), faces.allSatisfy({ Int($0) < Int(info.face_count) }),
              Set(faces).count == Int(info.face_count), vertices.allSatisfy({ v in
                  [v.position.x, v.position.y, v.position.z, v.normal.x, v.normal.y, v.normal.z].allSatisfy(\.isFinite)
              }) else { throw CADIntegrationError(message: "不正な頂点・法線・面IDを拒否しました。") }
        measurements.transferMS = milliseconds(DispatchTime.now().uptimeNanoseconds - start)
        measurements.vertices = vertices.count
        measurements.triangles = faces.count
        measurements.faces = Int(info.face_count)
        measurements.rustMeshBytes = info.buffer_bytes
        nextRevision += 1
        pending = (nextRevision, candidate, owned, wasCut, command.operation)
        transferred = true
        return PreparedCAD(token: nextRevision, mesh: CADMesh(body: candidate, revision: nextRevision,
            vertices: vertices, indices: indices, triangleFaces: faces, topology: topology, faceCount: Int(info.face_count), polygonMesh: polygonMesh),
            wasCut: wasCut, measurements: measurements)
    }

    /// Two-phase commit: called only after the new RealityKit resources are ready.
    func commit(_ token: UInt64) throws -> CommittedCAD {
        guard let p = pending, p.token == token else { throw CADIntegrationError(message: "古いCAD操作を拒否しました。") }
        switch p.operation {
        case .undo:
            guard undoStack.last?.body == p.body else { throw CADIntegrationError(message: "古いUndoです。") }
            undoStack.removeLast()
            if current != 0 { redoStack.append(State(body: current, wasCut: currentWasCut)) }
        case .redo:
            guard redoStack.last?.body == p.body else { throw CADIntegrationError(message: "古いRedoです。") }
            redoStack.removeLast()
            if current != 0 { undoStack.append(State(body: current, wasCut: currentWasCut)) }
        default:
            for state in redoStack { _ = sc_body_release(state.body) }
            redoStack.removeAll()
            if current != 0 { undoStack.append(State(body: current, wasCut: currentWasCut)) }
            if undoStack.count > historyLimit { _ = sc_body_release(undoStack.removeFirst().body) }
        }
        current = p.body; currentWasCut = p.wasCut; currentRevision = p.token
        pending = nil
        return CommittedCAD(canUndo: !undoStack.isEmpty, canRedo: !redoStack.isEmpty, wasCut: currentWasCut)
    }

    func abort(_ token: UInt64) {
        guard let p = pending, p.token == token else { return }
        if p.owned { _ = sc_body_release(p.body) }
        pending = nil
    }

    func registryStats() throws -> (UInt64, UInt64, UInt64) {
        var stats = SCRegistryStats()
        try checkCAD(sc_registry_stats(&stats))
        return (stats.live_bodies, stats.live_meshes, stats.mesh_bytes)
    }

    func shutdown() {
        if let p = pending, p.owned { _ = sc_body_release(p.body) }
        pending = nil
        if current != 0 { _ = sc_body_release(current) }
        for state in undoStack + redoStack { _ = sc_body_release(state.body) }
        undoStack.removeAll(); redoStack.removeAll()
        current = 0; currentRevision = 0; owner = nil
    }

    func record(_ m: CADMeasurements) {
        let header = "operation,box_ms,boolean_ms,direct_model_ms,conversion_ms,split_faces,swift_preview_ms,tessellation_ms,transfer_ms,lowlevelmesh_ms,render_prepare_ms,vertices,triangles,faces,footprint_bytes,live_bodies,live_meshes,rust_mesh_bytes\n"
        let line = "\(m.operation.replacingOccurrences(of: ",", with: ";")),\(m.boxMS),\(m.booleanMS),\(m.directModelMS),\(m.conversionMS),\(m.splitFaces),\(m.swiftPreviewMS),\(m.tessellationMS),\(m.transferMS),\(m.lowLevelMeshMS),\(m.renderPreparationMS),\(m.vertices),\(m.triangles),\(m.faces),\(m.footprintBytes),\(m.liveBodies),\(m.liveMeshes),\(m.rustMeshBytes)\n"
        print("SpatialModeling CAD: " + line.trimmingCharacters(in: .newlines))
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = directory.appendingPathComponent("spatial-modeling-cad-phase32-metrics.csv")
            if !FileManager.default.fileExists(atPath: url.path) { try Data(header.utf8).write(to: url) }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch { print("Metrics log write failed: \(error.localizedDescription)") }
    }
}
