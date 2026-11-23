// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import RealityKit
import simd
import SolidCoreProbe

@main struct ObjectTransformChecks {
    @MainActor static func all(_ root: Entity) -> [Entity] { [root] + root.children.flatMap(all) }
    static func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ message: String = "") { precondition(simd_length(a-b) < 0.00002, message) }
    static func volume(_ body: UInt64) -> Double { var v=0.0; precondition(sc_body_volume(body,&v)==0);return v }
    @MainActor static func main() async throws {
        EditTargetComponent.registerComponent(); CADTopologyTarget.registerComponent(); CADFaceTarget.registerComponent(); ObjectTarget.registerComponent()
        let w=WorkspaceModel(recordCADMeasurements: false)
        try w.prepareScene(); let space=Entity(); space.addChild(w.mesh.renderer.root);space.addChild(w.cad.renderer.root)
        w.immersiveState = .open; w.placeSessions(at: Transform(translation: [0,1.2,-0.9]))
        let initial=w.mesh.document.positions
        let vertex=all(w.mesh.renderer.root).first { $0.components[EditTargetComponent.self]?.selection == Selection(mode:.vertex,id:0) }!
        precondition(w.beginMeshInput(entity:vertex,at:.zero,activation:w.activation))
        w.finishMeshInput(at:[0.04,0.02,0],activation:w.activation)
        let edited=w.mesh.document.positions
        w.setSelectionMode(.object);precondition(w.isObjectMode)
        precondition(!w.beginMeshInput(entity:vertex,at:.zero,activation:w.activation))
        precondition(all(w.mesh.renderer.root).filter { $0.components[EditTargetComponent.self] != nil }.allSatisfy { !$0.isEnabledInHierarchy })
        let center=w.objectCenter, root=w.mesh.renderer.root
        let centerBefore=root.convert(position:center,to:space)
        precondition(w.beginObject(source:.slider,activation:w.activation))
        for percent in 101...200 { precondition(w.setDisplayPercent(Double(percent),commit:false)) }
        precondition(!w.canSwitchModes && !w.setMode(.cad))
        w.finishScaleSlider()
        close(root.scale,[2,2,2]);close(root.convert(position:center,to:space),centerBefore,"Scaling pivot")
        precondition(w.meshHistory.undo.count==2,"100 slider updates form one history item")
        precondition(w.performMesh(.undo));close(root.scale,[1,1,1]);precondition(w.mesh.document.positions==edited)
        precondition(w.performMesh(.undo));precondition(w.mesh.document.positions==initial)
        precondition(w.performMesh(.redo));precondition(w.mesh.document.positions==edited)
        precondition(w.performMesh(.redo));close(root.scale,[2,2,2])
        for invalid in [0.0,-1,.nan,.infinity,-.infinity,1000.1,0.99] {
            let before=root.transform.matrix
            precondition(!w.setDisplayPercent(invalid,commit:true));precondition(root.transform.matrix==before)
        }
        for valid in [1.0,1000,100] { precondition(w.setDisplayPercent(valid,commit:true));precondition(abs(w.meshObject.percent-valid)<0.001) }
        let beforeGesture=ObjectPose(root.transform), pivot=w.objectCenter
        let pivotWorld=root.convert(position:pivot,to:space)
        let rotation=simd_quatf(angle:.pi/3,axis:simd_normalize(SIMD3<Float>(1,1,0)))
        let translation=SIMD3<Float>(0.1,-0.05,0.12)
        precondition(w.beginObject(entity:w.meshObject.target,source:.gesture,activation:w.activation))
        for _ in 0..<20 { w.updateObject(translation:translation,magnification:1.5,rotation:rotation,activation:w.activation) }
        close(root.convert(position:pivot,to:space),pivotWorld+translation,"Combined center and translation")
        close(root.scale,[1.5,1.5,1.5],"No differential accumulation")
        // Child recognizers can finish at different times; missing values must retain their last deltas.
        w.updateObject(activation:w.activation)
        close(root.convert(position:pivot,to:space),pivotWorld+translation)
        close(root.scale,[1.5,1.5,1.5])
        w.finishObject(activation:w.activation)
        precondition(w.performMesh(.undo));precondition(ObjectPose(root.transform)==beforeGesture)
        precondition(w.performMesh(.redo))
        let transformed=ObjectPose(root.transform)
        precondition(w.beginObject(source:.gesture,activation:w.activation))
        w.updateObject(translation:[1,1,1],magnification:2,activation:w.activation);w.cancelObject()
        precondition(ObjectPose(root.transform)==transformed)
        precondition(w.performMesh(.reset));precondition(w.mesh.document.positions==initial && ObjectPose(root.transform)==transformed)
        w.resetObjectTransform();close(root.scale,[1,1,1]);close(root.position,[0,1.2,-0.9])
        precondition(w.performMesh(.undo));precondition(ObjectPose(root.transform)==transformed)
        let foreign=ObjectTransformCommand(commandID:UUID(),objectID:UUID(),expectedRevision:w.meshObject.revision,before:transformed,after:beforeGesture)
        precondition(!w.meshObject.execute(foreign))
        let command=ObjectTransformCommand(commandID:UUID(),objectID:w.mesh.objectID,expectedRevision:w.meshObject.revision,before:transformed,after:beforeGesture)
        let decoded=try JSONDecoder().decode(ObjectTransformCommand.self,from:JSONEncoder().encode(command))
        precondition(w.meshObject.execute(decoded));precondition(!w.meshObject.execute(decoded),"Stale revision rejected")

        precondition(w.setMode(.cad));let generated=await w.performCAD(.generate);precondition(generated)
        let body=w.cad.bodyID, cadRevision=w.cad.revision, baseVolume=volume(body)
        let originalCADHandle=all(w.cad.renderer.root).first { $0.components[CADTopologyTarget.self]?.selection.mode == .face }!
        w.setSelectionMode(.object)
        precondition(w.setDisplayPercent(200,commit:true))
        precondition(w.cad.bodyID==body && w.cad.revision==cadRevision && volume(body)==baseVolume)
        precondition(w.beginObject(source:.gesture,activation:w.activation))
        w.updateObject(translation:[0.15,0,0],rotation:simd_quatf(angle:.pi/4,axis:[0,1,0]),activation:w.activation)
        w.finishObject(activation:w.activation)
        let cadPose=ObjectPose(w.cad.renderer.root.transform)
        precondition(!w.selectCAD(originalCADHandle,activation:w.activation))
        w.setSelectionMode(.face)
        let target=originalCADHandle.components[CADTopologyTarget.self]!
        let face=w.cad.committedMesh!.topology.first { $0.selection==target.selection }!
        let localStart=face.position
        let localEnd=localStart+CADCoordinateConversion.offsetMeters(25,along:face.normal)
        let worldStart=w.cad.renderer.root.convert(position:localStart,to:space)
        let worldEnd=w.cad.renderer.root.convert(position:localEnd,to:space)
        precondition(abs(simd_length(worldEnd-worldStart)-0.05)<0.00001,"200% display makes 25mm CAD equal 50mm space")
        precondition(w.beginCADInput(entity:originalCADHandle,at:w.cad.renderer.root.convert(position:worldStart,from:space),activation:w.activation))
        w.finishCADInput(at:w.cad.renderer.root.convert(position:worldEnd,from:space),activation:w.activation,entity:originalCADHandle)
        await w.cad.waitForPreview()
        precondition(w.cad.bodyID != body && abs(w.cad.distanceMM-25)<0.01 && sc_body_validate(w.cad.bodyID)==0)
        precondition(abs(volume(w.cad.bodyID)-29_250_000)<3)
        precondition(ObjectPose(w.cad.renderer.root.transform)==cadPose)
        let undoFace=await w.performCAD(.undo);precondition(undoFace && w.cad.bodyID==body)
        let undoRotation=await w.performCAD(.undo);precondition(undoRotation);close(w.cad.renderer.root.scale,[2,2,2])
        let undoScale=await w.performCAD(.undo);precondition(undoScale);close(w.cad.renderer.root.scale,[1,1,1])
        for _ in 0..<3 { let ok=await w.performCAD(.redo);precondition(ok) }
        precondition(ObjectPose(w.cad.renderer.root.transform)==cadPose)
        let meshPose=ObjectPose(w.mesh.renderer.root.transform)
        for _ in 0..<10 { precondition(w.setMode(.mesh));precondition(ObjectPose(w.mesh.renderer.root.transform)==meshPose);precondition(w.setMode(.cad));precondition(ObjectPose(w.cad.renderer.root.transform)==cadPose) }
        w.endSpace();w.placeSessions(at:Transform(translation:[2,2,2]))
        precondition(ObjectPose(w.cad.renderer.root.transform)==cadPose,"Reopening preserves display pose")
        await w.cad.service.shutdown()
        let stats=try await w.cad.service.registryStats();precondition(stats.0==0 && stats.1==0)
        print("PASS: Object translation/rotation/uniform scale about model center; absolute deltas; cancellation; command validation")
        print("PASS: 1–1000% validation, slider transaction, chronological shape/Object Undo/Redo and separate Reset Shape/Transform")
        print("PASS: independent retained poses, element input isolation, CAD dimensions unchanged at 200%, rotated/scaled 25mm Push/Pull")
    }
}
