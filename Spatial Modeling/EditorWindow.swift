// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import SwiftUI
import simd

struct EditorWindow: View {
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var showConversionConfirmation = false
    @State private var conversionTarget: WorkspaceMode?
    @State private var scaleText = "100"
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Spatial Modeling").font(.title2.weight(.semibold))
            Picker("Modeling Mode", selection: Binding(get: { workspace.activeMode }, set: { workspace.setMode($0) })) {
                ForEach(WorkspaceMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            .disabled(!workspace.canSwitchModes)

            Picker("Selection", selection: Binding(get: { workspace.selectionMode }, set: { workspace.setSelectionMode($0) })) {
                ForEach(ModelingSelection.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }.pickerStyle(.segmented).disabled(!workspace.canSwitchModes)
            if workspace.isObjectMode { objectControls }
            if workspace.activeMode == .mesh { meshControls }
            else { cadControls }

            Button(workspace.activeMode == .mesh ? "Convert to CAD" : "Convert to Mesh") {
                let target:WorkspaceMode=workspace.activeMode == .mesh ? .cad : .mesh
                if workspace.conversionNeedsConfirmation(to:target) { conversionTarget=target;showConversionConfirmation=true }
                else { Task { await workspace.convert(to:target,replaceConfirmed:false) } }
            }.disabled(!workspace.canSwitchModes || !workspace.spaceReady || (workspace.activeMode == .cad && workspace.cad.committedMesh?.polygonMesh == nil))
            if workspace.conversionBusy { ProgressView("Converting…") }
            Divider()
            Button { Task { await toggleSpace() } } label: {
                Label(workspace.immersiveState == .open ? "Close ImmersiveSpace" : "Open ImmersiveSpace", systemImage: "visionpro")
                    .frame(maxWidth: .infinity)
            }
            .disabled(workspace.immersiveState == .opening || workspace.immersiveState == .closing || workspace.cad.isEditing || workspace.objectEditing || workspace.conversionBusy)
            .buttonStyle(.borderedProminent)
            if let error = workspace.errorMessage { errorText(error) }
        }
        .padding(28)
        .frame(width: 560)
        .confirmationDialog("Replace destination session?", isPresented:$showConversionConfirmation,titleVisibility:.visible) {
            Button("Convert and Replace") {
                guard let target=conversionTarget else { return }
                conversionTarget=nil
                Task { await workspace.convert(to:target,replaceConfirmed:true) }
            }
            Button("Cancel",role:.cancel) { conversionTarget=nil }
        } message: {
            Text("The source is kept. The destination geometry and display pose will be replaced; Undo can restore the destination.")
        }
        .onChange(of: workspace.activeMode) { _, _ in scaleText = String(format: "%.1f", workspace.activeObject.percent) }
        .onChange(of: workspace.activeObject.percent) { _, value in scaleText = String(format: "%.1f", value) }
        .task(id: workspace.activeMode) {
            if workspace.activeMode == .cad && !workspace.cad.hasBody { await workspace.performCAD(.generate) }
        }
    }

    private var meshControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button("Undo", systemImage: "arrow.uturn.backward") { workspace.performMesh(.undo) }.disabled(!workspace.canUndo)
                Button("Redo", systemImage: "arrow.uturn.forward") { workspace.performMesh(.redo) }.disabled(!workspace.canRedo)
                Spacer(minLength: 0)
                Button("Reset Shape", systemImage: "arrow.counterclockwise") { workspace.performMesh(.reset) }.disabled(workspace.mesh.isDragging || workspace.objectEditing)
            }
            .disabled(workspace.conversionBusy)
            Text(workspace.isObjectMode ? "Pinch and move the object. Use two hands to scale and rotate." : meshInstruction).font(.footnote).foregroundStyle(.secondary)
            if let error = workspace.mesh.errorMessage { errorText(error) }
        }
    }

    private var cadControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                cadButton("Generate Box", .generate)
                cadButton("Boolean Cut", .cut).disabled(!workspace.cad.hasBody || workspace.cad.hasCut)
                cadButton("Undo", .undo).disabled(!workspace.canUndo)
                cadButton("Redo", .redo).disabled(!workspace.canRedo)
                cadButton("Reset Shape", .reset)
            }.disabled(workspace.cad.isEditing || workspace.objectEditing || workspace.conversionBusy)
            Text("Display Scale: \(workspace.cadObject.percent, specifier: "%.1f")%")
            Text(cadDimensions).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(workspace.cad.busy ? "CAD演算中…" : workspace.isObjectMode ? "Pinch to move; use two hands to scale and rotate." : workspace.cad.selectionMode == .face
                 ? "面の球をピンチして、法線方向に押し引きします。"
                 : "頂点・辺をピンチして自由変形し、解除時にCADへ再構築します。")
                .font(.footnote).foregroundStyle(.secondary)
            if !workspace.isObjectMode && workspace.cad.selectionMode != .face {
                Text("Hybrid Direct Editing · Experimental").font(.caption).foregroundStyle(.secondary)
            }
            if workspace.cad.isDragging {
                Text(workspace.cad.selectionMode == .face ? String(format:"%+.1f mm",workspace.cad.distanceMM) : String(format:"Δ %.1f · %.1f · %.1f mm",workspace.cad.directDisplacementMM.x,workspace.cad.directDisplacementMM.y,workspace.cad.directDisplacementMM.z)).font(.title2.monospacedDigit())
                    .foregroundStyle(workspace.cad.previewValid ? Color.primary : .orange)
            }
            if let selected = workspace.cad.selection {
                Text("CAD \(selected.mode.rawValue) \(selected.id) · revision \(workspace.cad.revision)").font(.callout.monospacedDigit())
            }
            if workspace.cad.reconstructing { ProgressView("Rebuilding CAD…") }
            if workspace.cad.isDragging && workspace.cad.selectionMode != .face {
                Text(String(format:"Swift preview %.3f ms · Mesh %.3f ms",workspace.cad.hybridPreviewMS,workspace.cad.hybridMeshUpdateMS)).font(.caption.monospacedDigit())
            }
            if let m = workspace.cad.measurements {
                if m.conversionMS > 0 { Text(String(format:"Reconstruction %.3f ms · split %d faces",m.conversionMS,m.splitFaces)).font(.caption.monospacedDigit()) }
                Text("\(m.vertices)頂点 · \(m.triangles)三角形 · \(m.faces)面")
                    .font(.callout.monospacedDigit())
                Text(String(format: "CAD %.3f ms · Tess %.3f ms · Mesh %.3f ms · %.1f MiB", max(m.booleanMS, m.directModelMS), m.tessellationMS, m.lowLevelMeshMS, Double(m.footprintBytes) / 1_048_576))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let error = workspace.cad.errorMessage { errorText(error) }
        }
    }

    private var objectControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display Scale: \(workspace.activeObject.percent, specifier: "%.1f")%")
            Slider(value: Binding(get: { min(300, max(10, workspace.activeObject.percent)) },
                                  set: { _ = workspace.setDisplayPercent($0, commit: false) }),
                   in: 10...300, onEditingChanged: { editing in
                if editing { _ = workspace.beginObject(source: .slider, activation: workspace.activation) }
                else { workspace.finishScaleSlider() }
            })
            .disabled(!workspace.spaceReady || workspace.cad.isEditing || workspace.mesh.isDragging || workspace.activeObject.source == .gesture)
            HStack {
                TextField("Scale % (1–1000)", text: $scaleText).frame(width: 150)
                    .onSubmit { submitScale() }
                Text("%")
                Button("Apply") { submitScale() }
                Button("100%") { _ = workspace.setDisplayPercent(100, commit: true) }
                Spacer()
                Button("Reset Transform") { workspace.resetObjectTransform() }
            }.disabled(!workspace.canSwitchModes || !workspace.spaceReady)
            if let error = workspace.activeObject.errorMessage { errorText(error) }
            Text("Uniform display scale only. Shape dimensions are unchanged.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func submitScale() {
        let text = scaleText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
        guard let value = Double(text) else { workspace.activeObject.errorMessage = "Enter a finite scale from 1% to 1000%."; return }
        _ = workspace.setDisplayPercent(value, commit: true)
    }
    private var cadDimensions: String {
        let points = workspace.cad.committedMesh?.topology.filter { $0.selection.mode == .vertex }.map(\.position) ?? []
        guard let first = points.first else { return "CAD Dimensions: —" }
        let low = points.reduce(first) { simd_min($0,$1) }, high = points.reduce(first) { simd_max($0,$1) }
        let size = (high-low) * 1000
        return String(format: "CAD Dimensions (bounds): %.1f × %.1f × %.1f mm", size.x, size.z, size.y)
    }

    private func cadButton(_ title: String, _ action: CADAction) -> some View {
        Button(title) { Task { await workspace.performCAD(action) } }
    }
    private func errorText(_ error: String) -> some View {
        Text(error).font(.footnote).foregroundStyle(.orange).textSelection(.enabled)
    }
    private var meshInstruction: String {
        switch workspace.mesh.mode {
        case .vertex: "頂点の球を見てピンチし、手を動かして変形します。"
        case .edge: "辺の中点にある球を見てピンチし、辺を平行移動します。"
        case .face: "面の中央にある球を見てピンチし、面を平行移動します。"
        }
    }

    @MainActor private func toggleSpace() async {
        workspace.errorMessage = nil
        switch workspace.immersiveState {
        case .closed:
            workspace.immersiveState = .opening
            switch await openImmersiveSpace(id: WorkspaceModel.immersiveID) {
            case .opened: workspace.immersiveState = .open
            case .userCancelled: workspace.immersiveState = .closed
            case .error:
                workspace.immersiveState = .closed
                workspace.errorMessage = "ImmersiveSpaceを開けませんでした。再度お試しください。"
            @unknown default: workspace.immersiveState = .closed
            }
        case .open:
            workspace.immersiveState = .closing
            workspace.cancelMeshInput()
            await dismissImmersiveSpace()
            workspace.immersiveState = .closed
        case .opening, .closing: break
        }
    }
}
