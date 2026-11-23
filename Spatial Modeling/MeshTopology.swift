// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation

typealias VertexID = Int

struct Vertex: Identifiable, Equatable {
    let id: VertexID
    var position: SIMD3<Float>
}

struct Edge: Identifiable, Equatable {
    let id: Int
    let vertexIDs: [VertexID]
}

struct Face: Identifiable, Equatable {
    let id: Int
    /// Counterclockwise when viewed from outside the mesh.
    let vertexIDs: [VertexID]
}

enum EditMode: String, CaseIterable, Identifiable, Sendable {
    case vertex = "Vertex", edge = "Edge", face = "Face"
    var id: Self { self }
}

struct Selection: Equatable, Hashable, Sendable {
    let mode: EditMode
    let id: Int
}
