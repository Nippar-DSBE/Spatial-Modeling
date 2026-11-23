// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import simd
import SolidCoreProbe

struct CADRenderVertex: Sendable {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
}

/// The only CAD mm/Z-up -> RealityKit m/Y-up conversion in this project.
/// The rotation is right-handed: (x,y,z) -> (x,z,-y).
enum CADCoordinateConversion {
    static func cadPositionMM(_ p: SIMD3<Float>) -> SIMD3<Double> {
        [Double(p.x)*1000,Double(-p.z)*1000,Double(p.y)*1000]
    }
    static func positionMM(_ p: SIMD3<Double>) -> SIMD3<Float> {
        SIMD3<Float>(Float(p.x), Float(p.z), Float(-p.y)) * 0.001
    }
    static func normal(_ n: SIMD3<Double>) -> SIMD3<Float> {
        let v = SIMD3<Float>(Float(n.x), Float(n.z), Float(-n.y))
        return simd_length_squared(v) > 1e-12 ? simd_normalize(v) : .zero
    }
    static func distanceMM(_ deltaMeters: SIMD3<Float>, along normal: SIMD3<Float>) -> Double {
        Double(simd_dot(deltaMeters, normal)) * 1000
    }
    static func offsetMeters(_ distanceMM: Double, along normal: SIMD3<Float>) -> SIMD3<Float> {
        normal * Float(distanceMM * 0.001)
    }
    static func vertex(_ v: SCVertex) -> CADRenderVertex {
        let p = SIMD3<Float>(v.x, v.z, -v.y) * 0.001
        let n = SIMD3<Float>(v.nx, v.nz, -v.ny)
        return CADRenderVertex(position: p, normal: simd_normalize(n))
    }
}
