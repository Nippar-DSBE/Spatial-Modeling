// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import simd

@main
struct MeshCoreChecks {
    static func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ message: String) {
        precondition(simd_distance(a, b) < 0.000001, message)
    }

    static func main() {
        let cube = CubePrimitive.make()
        precondition(cube.vertices.count == 8 && cube.edges.count == 12 && cube.faces.count == 6)
        let geometry = MeshGeometry(document: cube)
        precondition(geometry.triangles.count == 12)
        precondition(geometry.logicalToRender.values.flatMap { $0 }.sorted() == Array(0..<36))
        let render = geometry.vertices(positions: cube.positions)
        for triangle in stride(from: 0, to: render.count, by: 3) {
            let center = (render[triangle].position + render[triangle+1].position + render[triangle+2].position) / 3
            precondition(simd_dot(center, render[triangle].normal) > 0, "Outward triangle winding")
        }

        for mode in EditMode.allCases {
            var document = cube
            let selection = Selection(mode: mode, id: 0)
            let ids = document.vertexIDs(for: selection)
            precondition(ids.count == (mode == .vertex ? 1 : mode == .edge ? 2 : 4))
            let start: SIMD3<Float> = [0.2, -0.1, 0.4]
            let delta: SIMD3<Float> = [0.08, 0.04, -0.12]
            document.beginDrag(selection, at: start)
            precondition(document.positions == cube.positions, "No jump at pinch start")
            // A competing selection during a pinch must not replace the original.
            document.beginDrag(Selection(mode: mode, id: 1), at: [9,9,9])
            precondition(document.drag?.selection == selection)
            for _ in 0..<1000 { document.updateDrag(to: start + delta) }
            for vertex in document.vertices {
                near(vertex.position, cube.positions[vertex.id]! + (ids.contains(vertex.id) ? delta : .zero), "Exact selected set; no accumulated drift")
            }
            let orderedIDs = ids.sorted()
            if let first = orderedIDs.first {
                for id in orderedIDs.dropFirst() {
                    near(document.positions[id]! - document.positions[first]!,
                         cube.positions[id]! - cube.positions[first]!, "Edge/face relative shape stays fixed")
                }
            }
            precondition(document.history.undoStack.isEmpty, "No history during drag")
            let changed = document.positions
            document.finishDrag()
            precondition(document.history.undoStack.count == 1)
            document.undo()
            precondition(document.positions == cube.positions)
            document.redo()
            precondition(document.positions == changed)
            document.reset()
            precondition(document.positions == cube.positions)
            document.undo()
            precondition(document.positions == changed, "Reset is undoable")
            document.beginDrag(selection, at: start)
            document.updateDrag(to: start + delta)
            document.cancelDrag()
            precondition(document.positions == changed && document.drag == nil)
            document.beginDrag(selection, at: start)
            document.finishDrag()
            precondition(document.history.canRedo, "No-op preserves redo")
            document.beginDrag(selection, at: start)
            document.updateDrag(to: start + delta)
            document.finishDrag()
            precondition(!document.history.canRedo, "New edit clears redo branch")
            print("PASS: \(mode.rawValue) translation, fixed target, drift, undo/redo/reset/cancel")
        }

        var deformed = cube
        deformed.beginDrag(Selection(mode: .vertex, id: 0), at: .zero)
        deformed.updateDrag(to: [0.03, 0.07, -0.04])
        let deformedRender = geometry.vertices(positions: deformed.positions)
        for index in geometry.logicalToRender[0]! {
            precondition(deformedRender[index].position == deformed.positions[0]!)
        }
        precondition(deformedRender.count == 36 && deformedRender.allSatisfy { $0.normal.allFinite })
        // Collapse all corners of one face and verify finite fallback normals.
        var collapsed = cube.positions
        for id in cube.faces[0].vertexIDs { collapsed[id] = .zero }
        precondition(geometry.vertices(positions: collapsed).allSatisfy { $0.normal.allFinite })
        let before = deformed.positions
        deformed.updateDrag(to: [Float.nan, 0, 0])
        precondition(deformed.positions == before)
        print("PASS: topology, outward normals, render mapping, nonplanar/collapsed faces, nonfinite input")
    }
}
