// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation

struct DragEdit {
    let selection: Selection
    let vertexIDs: Set<VertexID>
    let initialPositions: PositionSnapshot
    let startLocation: SIMD3<Float>
}

struct MeshDocument {
    private(set) var vertices: [Vertex]
    let edges: [Edge]
    let faces: [Face]
    private(set) var selection: Selection?
    private(set) var drag: DragEdit?
    private(set) var history = EditHistory()
    private let initialPositions: PositionSnapshot

    init(vertices: [Vertex], edges: [Edge], faces: [Face]) {
        self.vertices = vertices
        self.edges = edges
        self.faces = faces
        initialPositions = Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0.position) })
    }

    var positions: PositionSnapshot {
        Dictionary(uniqueKeysWithValues: vertices.map { ($0.id, $0.position) })
    }

    func vertexIDs(for selection: Selection) -> Set<VertexID> {
        switch selection.mode {
        case .vertex: return vertices.contains(where: { $0.id == selection.id }) ? [selection.id] : []
        case .edge: return Set(edges.first(where: { $0.id == selection.id })?.vertexIDs ?? [])
        case .face: return Set(faces.first(where: { $0.id == selection.id })?.vertexIDs ?? [])
        }
    }

    mutating func beginDrag(_ target: Selection, at location: SIMD3<Float>) {
        guard drag == nil, location.allFinite else { return }
        let ids = vertexIDs(for: target)
        guard !ids.isEmpty else { return }
        selection = target
        drag = DragEdit(selection: target, vertexIDs: ids, initialPositions: positions, startLocation: location)
    }

    mutating func updateDrag(to location: SIMD3<Float>) {
        guard let drag, location.allFinite else { return }
        let delta = location - drag.startLocation
        guard delta.allFinite else { return }
        for index in vertices.indices where drag.vertexIDs.contains(vertices[index].id) {
            if let initial = drag.initialPositions[vertices[index].id] {
                let position = initial + delta
                guard position.allFinite else { continue }
                vertices[index].position = position
            }
        }
    }

    mutating func finishDrag() {
        guard let drag else { return }
        history.record(before: drag.initialPositions, after: positions)
        self.drag = nil
    }

    mutating func cancelDrag() {
        guard let drag else { return }
        restore(drag.initialPositions)
        self.drag = nil
        selection = nil
    }

    mutating func clearSelection() { selection = nil }

    mutating func undo() {
        guard drag == nil, let snapshot = history.undo(current: positions) else { return }
        restore(snapshot)
        selection = nil
    }

    mutating func redo() {
        guard drag == nil, let snapshot = history.redo(current: positions) else { return }
        restore(snapshot)
        selection = nil
    }

    mutating func reset() {
        guard drag == nil else { return }
        let before = positions
        restore(initialPositions)
        history.record(before: before, after: positions)
        selection = nil
    }

    private mutating func restore(_ snapshot: PositionSnapshot) {
        for index in vertices.indices {
            if let position = snapshot[vertices[index].id] { vertices[index].position = position }
        }
    }
}

extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}
