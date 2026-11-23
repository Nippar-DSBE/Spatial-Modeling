// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import SwiftUI
import RealityKit

struct ImmersiveEditorView: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.scenePhase) private var scenePhase
    @State private var placement = ScenePlacement()
    @GestureState private var meshGestureActive = false
    @GestureState private var cadGestureActive = false

    var body: some View {
        // Captured by this activation's handlers; delayed callbacks cannot use the next mode's state.
        let activation = workspace.activation
        RealityView { content, attachments in
            do { try workspace.prepareScene() }
            catch { workspace.errorMessage = "メッシュの初期化に失敗しました: \(error.localizedDescription)" }
            content.add(workspace.mesh.renderer.root)
            content.add(workspace.cad.renderer.root)
            if let label = attachments.entity(for: "cad-distance") { workspace.cad.renderer.root.addChild(label); label.isEnabled = false }
        } update: { _, attachments in
            workspace.synchronizeObjectTargets()
            if let label = attachments.entity(for: "cad-distance") {
                if label.parent !== workspace.cad.renderer.root { workspace.cad.renderer.root.addChild(label) }
                label.isEnabled = workspace.activeMode == .cad && workspace.cad.isDragging && workspace.spaceReady
                label.position = workspace.cad.dragLabelPosition
            }
        } attachments: {
            Attachment(id: "cad-distance") {
                Text(workspace.cad.selectionMode == .face ? String(format:"%+.1f mm",workspace.cad.distanceMM) : String(format:"Δ %.1f · %.1f · %.1f mm",workspace.cad.directDisplacementMM.x,workspace.cad.directDisplacementMM.y,workspace.cad.directDisplacementMM.z))
                    .font(.title3.monospacedDigit()).padding(10)
                    .foregroundStyle(workspace.cad.previewValid ? Color.primary : .orange)
                    .glassBackgroundEffect().allowsHitTesting(false)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToEntity(where: .has(EditTargetComponent.self))
                .updating($meshGestureActive) { _, active, _ in active = true }
                .onChanged { InteractionController.changed($0, workspace: workspace, activation: activation) }
                .onEnded { InteractionController.ended($0, workspace: workspace, activation: activation) },
            including: workspace.activeMode == .mesh && !workspace.meshObjectMode ? .all : .none
        )
        .simultaneousGesture(
            SpatialTapGesture().targetedToEntity(where: .has(CADTopologyTarget.self))
                .onEnded { workspace.selectCAD($0.entity, activation: activation) },
            including: workspace.activeMode == .cad && !workspace.cadObjectMode ? .all : .none
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).targetedToEntity(where: .has(CADTopologyTarget.self))
                .updating($cadGestureActive) { _, active, _ in active = true }
                .onChanged { value in
                    let root = workspace.cad.renderer.root
                    if !workspace.cad.isDragging {
                        guard workspace.beginCADInput(entity: value.entity,
                            at: value.convert(value.startLocation3D, from: .local, to: root), activation: activation) else { return }
                    }
                    workspace.updateCADInput(to: value.convert(value.location3D, from: .local, to: root), activation: activation, entity: value.entity)
                }
                .onEnded { value in
                    workspace.finishCADInput(at: value.convert(value.location3D, from: .local, to: workspace.cad.renderer.root), activation: activation, entity: value.entity)
                },
            including: workspace.activeMode == .cad && !workspace.cadObjectMode ? .all : .none
        )
        .onChange(of: cadGestureActive) { _, active in
            if !active { workspace.cad.cancelDrag(unlessEnding: true) }
        }
        .modifier(ObjectGestureModifier())
        .task { await placement.place(workspace: workspace) }
        .onAppear { workspace.immersiveState = .open }
        .onChange(of: meshGestureActive) { _, active in
            if !active { workspace.cancelMeshInput(activation: activation) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { workspace.cancelMeshInput(); workspace.cad.cancelDrag(); workspace.cancelObject() }
        }
        .onDisappear {
            placement.stop()
            workspace.endSpace()
        }
    }
}
