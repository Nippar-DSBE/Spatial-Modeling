// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation

// Versioned command envelope: independent of gestures, RealityView and transport.
enum CADSelectionMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case vertex = "Vertex", edge = "Edge", face = "Face"
    var id: Self { self }
    var kind: UInt32 { switch self { case .vertex: 0; case .edge: 1; case .face: 2 } }
}
struct CADSelection: Hashable, Codable, Sendable {
    let mode: CADSelectionMode
    let id: UInt32
}
enum CADOperation: Codable, Sendable {
    case generate, cut, undo, redo, reset
    case offsetFace(face: UInt32, distanceMM: Double)
    case replaceMesh(CADPolygonMesh)
}
struct CADCommand: Codable, Sendable {
    let version: UInt32
    let commandID: UUID
    let objectID: UUID
    let expectedRevision: UInt64
    let operation: CADOperation
    init(objectID: UUID, revision: UInt64, operation: CADOperation) {
        version = 1; commandID = UUID(); self.objectID = objectID
        expectedRevision = revision; self.operation = operation
    }
}
struct CADTopologyElement: Sendable {
    let selection: CADSelection
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
    let editable: Bool
}
