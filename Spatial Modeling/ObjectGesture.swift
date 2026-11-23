// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import SwiftUI
import RealityKit

/// One simultaneous recognizer keeps one-hand drag and two-hand scale/rotation in one transaction.
/// It targets ObjectTarget only; element gestures are masked out while Object is selected.
struct ObjectGestureModifier: ViewModifier {
    @Environment(WorkspaceModel.self) private var workspace
    @GestureState private var active = false
    private typealias Combined = SimultaneousGesture<SimultaneousGesture<DragGesture, MagnifyGesture>, RotateGesture3D>
    func body(content: Content) -> some View {
        let activation = workspace.activation
        let revision = workspace.activeObject.revision
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .simultaneously(with: MagnifyGesture())
                .simultaneously(with: RotateGesture3D())
                .targetedToEntity(where: .has(ObjectTarget.self))
                .updating($active) { _, state, _ in state = true }
                .onChanged { apply($0, activation: activation, revision: revision) }
                .onEnded { value in
                    guard workspace.activeObject.revision == revision else { return }
                    apply(value, activation: activation, revision: revision)
                    workspace.finishObject(activation: activation)
                },
            including: workspace.isObjectMode ? .all : .none
        )
        .onChange(of: active) { _, active in
            if !active && workspace.activeObject.source == .gesture && workspace.activeObject.revision == revision { workspace.cancelObject() }
        }
    }
    private func apply(_ value: EntityTargetValue<Combined.Value>, activation: UInt64, revision: UInt64) {
        guard workspace.isObjectMode, workspace.activation == activation, workspace.activeObject.revision == revision else { return }
        let session = workspace.activeObject
        if !session.isEditing {
            guard workspace.beginObject(entity: value.entity, source: .gesture, activation: activation) else { return }
        }
        guard session.source == .gesture,
              let target = value.entity.components[ObjectTarget.self], target.objectID == session.objectID,
              target.revision == session.revision else { return }
        let drag = value.gestureValue.first?.first
        let magnify = value.gestureValue.first?.second
        let rotate = value.gestureValue.second
        let translation: SIMD3<Float>?
        if let drag {
            // Scene space does not move/scale underneath the gesture like the model's local space does.
            translation = value.convert(drag.location3D, from: .local, to: .scene)
                - value.convert(drag.startLocation3D, from: .local, to: .scene)
        } else { translation = nil }
        let rotation = rotate.map { value.convert($0.rotation, from: .local, to: .scene) }
        workspace.updateObject(translation: translation, magnification: magnify.map { Float($0.magnification) },
                               rotation: rotation, activation: activation)
    }
}
