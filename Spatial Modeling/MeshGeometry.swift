// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import simd

struct RenderVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

/// Fixed topology: a convex polygon fan, with independent vertices per triangle.
/// This keeps nonplanar quads drawable and avoids smoothing across cube faces.
struct MeshGeometry {
    struct Triangle {
        let faceID: Int
        let vertexIDs: [VertexID]
    }
    let triangles: [Triangle]
    let logicalToRender: [VertexID: [Int]]

    init(document: MeshDocument) {
        var triangles: [Triangle] = []
        for face in document.faces where face.vertexIDs.count >= 3 {
            let ids = Self.triangulate(face.vertexIDs, positions: document.positions)
            for triangle in ids { triangles.append(Triangle(faceID: face.id, vertexIDs: triangle)) }
        }
        self.triangles = triangles
        var mapping: [VertexID: [Int]] = [:]
        for (triangleIndex, triangle) in triangles.enumerated() {
            for (corner, id) in triangle.vertexIDs.enumerated() {
                mapping[id, default: []].append(triangleIndex * 3 + corner)
            }
        }
        logicalToRender = mapping
    }

    /// Ear clipping retains logical polygon boundaries; diagonals exist only in display geometry.
    /// Mesh Mode may deliberately make invalid/degenerate faces, so its display falls back to a fan.
    private static func triangulate(_ ids: [VertexID], positions: PositionSnapshot) -> [[VertexID]] {
        let fallback = (1..<(ids.count-1)).map { [ids[0],ids[$0],ids[$0+1]] }
        guard ids.count > 3 else { return fallback }
        let origin=positions[ids[0]]!
        var normal=SIMD3<Float>.zero
        for i in ids.indices { normal += simd_cross(positions[ids[i]]!-origin,positions[ids[(i+1)%ids.count]]!-origin) }
        guard simd_length_squared(normal)>1e-14 else { return fallback }
        normal=simd_normalize(normal)
        let first=positions[ids[1]]!-origin
        guard simd_length_squared(first)>1e-14 else { return fallback }
        let v=simd_normalize(simd_cross(normal,first)),u=simd_cross(v,normal)
        func uv(_ id:VertexID)->SIMD2<Float> { let p=positions[id]!-origin;return [simd_dot(p,u),simd_dot(p,v)] }
        func area(_ a:SIMD2<Float>,_ b:SIMD2<Float>,_ c:SIMD2<Float>)->Float { (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) }
        var left=ids,result:[[VertexID]]=[]
        while left.count>3 {
            var chosen:Int?
            for step in left.indices {
                let i=(step+1)%left.count,previous=(i+left.count-1)%left.count,next=(i+1)%left.count
                let a=uv(left[previous]),b=uv(left[i]),c=uv(left[next])
                guard area(a,b,c)>1e-12 else { continue }
                let contains=left.indices.contains { j in
                    guard j != previous && j != i && j != next else { return false }
                    let p=uv(left[j]);return area(a,b,p)>=(-1e-12) && area(b,c,p)>=(-1e-12) && area(c,a,p)>=(-1e-12)
                }
                if !contains { chosen=i;result.append([left[previous],left[i],left[next]]);break }
            }
            guard let chosen else { return fallback }
            left.remove(at:chosen)
        }
        result.append(left);return result
    }

    func vertices(positions: PositionSnapshot) -> [RenderVertex] {
        triangles.flatMap { triangle -> [RenderVertex] in
            let points = triangle.vertexIDs.map { positions[$0]! }
            let cross = simd_cross(points[1] - points[0], points[2] - points[0])
            let length = simd_length(cross)
            // Collapsed triangles must not write NaNs into the GPU buffer.
            let normal: SIMD3<Float> = length.isFinite && length > 0.0000001
                ? cross / length : [0, 1, 0]
            return points.map { RenderVertex(position: $0, normal: normal) }
        }
    }
}
