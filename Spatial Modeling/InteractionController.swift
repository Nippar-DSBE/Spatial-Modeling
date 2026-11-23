// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import SwiftUI
import RealityKit

@MainActor enum InteractionController {
    static func changed(_ value: EntityTargetValue<DragGesture.Value>, workspace: WorkspaceModel, activation: UInt64) {
        guard workspace.activeMode == .mesh, workspace.activation == activation else { return }
        let root = workspace.mesh.renderer.root
        if workspace.meshInput == nil {
            let start = value.convert(value.startLocation3D, from: .local, to: root)
            guard workspace.beginMeshInput(entity: value.entity, at: start, activation: activation) else { return }
        }
        workspace.updateMeshInput(to: value.convert(value.location3D, from: .local, to: root), activation: activation)
    }

    static func ended(_ value: EntityTargetValue<DragGesture.Value>, workspace: WorkspaceModel, activation: UInt64) {
        workspace.finishMeshInput(at: value.convert(value.location3D, from: .local, to: workspace.mesh.renderer.root), activation: activation)
    }
}
