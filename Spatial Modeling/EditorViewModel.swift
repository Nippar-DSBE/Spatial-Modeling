// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import SwiftUI
import RealityKit
import Observation

enum ImmersiveState { case closed, opening, open, closing }

@MainActor @Observable
final class EditorViewModel {
    let objectID: UUID
    private(set) var revision: UInt64 = 0
    private(set) var document = CubePrimitive.make()
    private(set) var mode: EditMode = .vertex
    var errorMessage: String?
    var isPlaced = false
    @ObservationIgnored let renderer: MeshRenderer
    var isDragging: Bool { document.drag != nil }
    var canUndo: Bool { document.history.canUndo && !isDragging }
    var canRedo: Bool { document.history.canRedo && !isDragging }

    init() {
        let id = UUID()
        objectID = id
        renderer = MeshRenderer(objectID: id)
    }

    func prepareRenderer() throws {
        try renderer.prepare(document: document, mode: mode, revision: revision)
    }

    func replaceDocument(_ next: MeshDocument) throws {
        try renderer.replace(document:next,mode:mode,revision:revision+1)
        document=next;revision+=1
    }
    func setMode(_ mode: EditMode) {
        guard !isDragging, self.mode != mode else { return }
        self.mode = mode
        document.clearSelection()
        revision += 1
        refresh()
    }

    func beginDrag(_ selection: Selection, at location: SIMD3<Float>) {
        guard isPlaced, selection.mode == mode else { return }
        document.beginDrag(selection, at: location)
    }

    func updateDrag(to location: SIMD3<Float>) {
        document.updateDrag(to: location)
        refresh()
    }

    func finishDrag() {
        guard isDragging else { return }
        document.finishDrag(); revision += 1; refresh()
    }
    func cancelDrag() {
        guard isDragging else { return }
        document.cancelDrag(); revision += 1; refresh()
    }
    func undo() {
        guard canUndo else { return }
        document.undo(); revision += 1; refresh()
    }
    func redo() {
        guard canRedo else { return }
        document.redo(); revision += 1; refresh()
    }
    func reset() {
        guard !isDragging else { return }
        document.reset(); revision += 1; refresh()
    }
    func refresh() { renderer.update(document: document, mode: mode, revision: revision) }
}
