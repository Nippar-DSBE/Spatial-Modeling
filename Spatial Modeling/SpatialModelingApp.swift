// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import SwiftUI
import RealityKit

@main struct SpatialModelingApp: App {
    @State private var workspace = WorkspaceModel()
    init() {
        ObjectTarget.registerComponent()
        EditTargetComponent.registerComponent()
        CADFaceTarget.registerComponent()
        CADTopologyTarget.registerComponent()
    }
    var body: some SwiftUI.Scene {
        WindowGroup { EditorWindow().environment(workspace) }
            .windowResizability(.contentSize)
        ImmersiveSpace(id: WorkspaceModel.immersiveID) { ImmersiveEditorView().environment(workspace) }
            .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
