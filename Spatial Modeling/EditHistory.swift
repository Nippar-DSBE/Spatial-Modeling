// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation

typealias PositionSnapshot = [VertexID: SIMD3<Float>]

struct EditHistory {
    private(set) var undoStack: [PositionSnapshot] = []
    private(set) var redoStack: [PositionSnapshot] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    mutating func record(before: PositionSnapshot, after: PositionSnapshot) {
        guard before != after else { return }
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    mutating func undo(current: PositionSnapshot) -> PositionSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    mutating func redo(current: PositionSnapshot) -> PositionSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
