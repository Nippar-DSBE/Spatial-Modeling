// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation

enum CubePrimitive {
    static func make(size: Float = 0.3) -> MeshDocument {
        let h = size / 2
        let points: [SIMD3<Float>] = [
            [-h, -h, -h], [h, -h, -h], [h, h, -h], [-h, h, -h],
            [-h, -h, h], [h, -h, h], [h, h, h], [-h, h, h]
        ]
        let edges = [[0,1], [1,2], [2,3], [3,0], [4,5], [5,6],
                     [6,7], [7,4], [0,4], [1,5], [2,6], [3,7]]
        let faces = [[0,3,2,1], [4,5,6,7], [0,4,7,3],
                     [1,2,6,5], [0,1,5,4], [3,7,6,2]]
        return MeshDocument(
            vertices: points.enumerated().map { Vertex(id: $0.offset, position: $0.element) },
            edges: edges.enumerated().map { Edge(id: $0.offset, vertexIDs: $0.element) },
            faces: faces.enumerated().map { Face(id: $0.offset, vertexIDs: $0.element) }
        )
    }
}
