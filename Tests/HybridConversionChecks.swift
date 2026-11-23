// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT
import Foundation
import RealityKit
import simd
import SolidCoreProbe

@main struct HybridConversionChecks {
    @MainActor static func all(_ e:Entity)->[Entity] { [e]+e.children.flatMap(all) }
    @MainActor static func cadHandle(_ w:WorkspaceModel,_ mode:CADSelectionMode,id:UInt32=0)->Entity {
        all(w.cad.renderer.root).first { $0.components[CADTopologyTarget.self]?.selection == CADSelection(mode:mode,id:id) }!
    }
    @MainActor static func meshHandle(_ w:WorkspaceModel,_ mode:EditMode,id:Int=0)->Entity {
        all(w.mesh.renderer.root).first { $0.components[EditTargetComponent.self]?.selection == Selection(mode:mode,id:id) }!
    }
    static func volume(_ id:UInt64)->Double { var v=0.0;precondition(sc_body_volume(id,&v)==0);return v }
    @MainActor static func action(_ w:WorkspaceModel,_ a:CADAction) async { let ok=await w.performCAD(a);precondition(ok,w.cad.errorMessage ?? "CAD action failed") }
    @MainActor static func convert(_ w:WorkspaceModel,to:WorkspaceMode,confirmed:Bool=true) async {
        let ok=await w.convert(to:to,replaceConfirmed:confirmed);precondition(ok,w.errorMessage ?? "Conversion failed")
    }
    @MainActor static func drag(_ w:WorkspaceModel,mode:CADSelectionMode,id:UInt32=0,delta:SIMD3<Float>,space:Entity) async -> UInt64 {
        w.setCADSelectionMode(mode)
        let entity=cadHandle(w,mode,id:id),before=w.cad.bodyID
        let revision=w.cad.revision,pose=ObjectPose(w.cad.renderer.root.transform)
        let localStart=entity.position
        let worldStart=w.cad.renderer.root.convert(position:localStart,to:space)
        let worldEnd=w.cad.renderer.root.convert(position:localStart+delta,to:space)
        precondition(w.beginCADInput(entity:entity,at:w.cad.renderer.root.convert(position:worldStart,from:space),activation:w.activation))
        w.updateCADInput(to:localStart+delta*0.5,activation:w.activation,entity:entity)
        w.updateCADInput(to:w.cad.renderer.root.convert(position:worldEnd,from:space),activation:w.activation,entity:entity)
        precondition(w.cad.bodyID==before && w.cad.revision==revision && !w.canSwitchModes && !w.setMode(.mesh),"Preview never changes formal B-rep")
        let preview=w.cad.hybridPreviewMS,update=w.cad.hybridMeshUpdateMS
        w.finishCADInput(at:localStart+delta,activation:w.activation,entity:entity)
        await w.cad.waitForPreview()
        precondition(!w.cad.isEditing && w.cad.bodyID != before,w.cad.errorMessage ?? "Hybrid commit failed")
        precondition(ObjectPose(w.cad.renderer.root.transform)==pose && sc_body_validate(w.cad.bodyID)==0)
        precondition(!w.selectCAD(entity,activation:w.activation),"Old record IDs rejected")
        let m=w.cad.measurements!
        print(String(format:"MEASURE %@ SwiftPreview=%.3f MeshWrite=%.3f Reconstruction=%.3f Tess=%.3f ms faces=%d split=%d",mode.rawValue,preview,update,m.conversionMS,m.tessellationMS,m.faces,m.splitFaces))
        return before
    }
    @MainActor static func main() async throws {
        EditTargetComponent.registerComponent();CADTopologyTarget.registerComponent();CADFaceTarget.registerComponent();ObjectTarget.registerComponent()
        // All existing Mesh deformation modes feed the same polygon conversion path.
        for mode in EditMode.allCases {
            var source=CubePrimitive.make();source.beginDrag(Selection(mode:mode,id:0),at:.zero)
            source.updateDrag(to:[0.02,0.01,0.015]);source.finishDrag()
            let input=try CADPolygonMesh.from(source),result=try input.createBody()
            precondition(sc_body_validate(result.body)==0 && volume(result.body)>0)
            print(String(format:"MEASURE Mesh %@ conversion=%.3f ms split=%d",mode.rawValue,result.milliseconds,result.splitFaces))
            precondition(sc_body_release(result.body)==0)
        }
        // Native primitive Box -> logical Mesh -> native CAD, including undo of replacement.
        let primitive=WorkspaceModel(recordCADMeasurements:false)
        try primitive.prepareScene();primitive.immersiveState = .open;primitive.placeSessions(at:Transform())
        precondition(primitive.setMode(.cad));await action(primitive,.generate)
        let primitiveID=primitive.cad.bodyID
        await convert(primitive,to:.mesh)
        precondition(primitive.mesh.document.vertices.count==8 && primitive.mesh.document.edges.count==12 && primitive.mesh.document.faces.count==6)
        await convert(primitive,to:.cad)
        precondition(abs(volume(primitive.cad.bodyID)-27_000_000)<10)
        await action(primitive,.undo);precondition(primitive.cad.bodyID==primitiveID)
        await primitive.cad.service.shutdown()
        let w=WorkspaceModel(recordCADMeasurements:false)
        try w.prepareScene();let space=Entity();space.addChild(w.mesh.renderer.root);space.addChild(w.cad.renderer.root)
        w.immersiveState = .open;w.placeSessions(at:Transform(translation:[0,1.2,-0.9]))
        let original=w.mesh.document.positions
        await convert(w,to:.cad,confirmed:false)
        precondition(abs(volume(w.cad.bodyID)-27_000_000)<10 && w.cad.measurements?.faces==6)
        precondition(w.mesh.document.positions==original,"Source kept")
        let polygons=w.cad.committedMesh!.polygonMesh!
        precondition(polygons.pointsMM.count==8 && polygons.edges.count==12 && polygons.faces.count==6)
        precondition(polygons.faces.allSatisfy { $0.count==4 },"Preserve logical quads, not tessellation diagonals")
        let body=w.cad.bodyID
        let rejected=await w.convert(to:.mesh,replaceConfirmed:false)
        precondition(!rejected && w.cad.bodyID==body && w.activeMode == .cad)
        await convert(w,to:.mesh)
        precondition(w.cad.bodyID==body && w.mesh.document.edges.count==12)
        let imported=w.mesh.document.positions
        let vertex=meshHandle(w,.vertex)
        precondition(w.beginMeshInput(entity:vertex,at:.zero,activation:w.activation))
        w.finishMeshInput(at:[0.02,0.01,0.015],activation:w.activation)
        let deformed=w.mesh.document.positions
        precondition(w.performMesh(.undo) && w.mesh.document.positions==imported)
        precondition(w.performMesh(.undo) && w.mesh.document.positions==original)
        precondition(w.performMesh(.redo) && w.mesh.document.positions==imported)
        precondition(w.performMesh(.redo) && w.mesh.document.positions==deformed,"Conversion snapshots retain child redo state")
        w.setSelectionMode(.object);precondition(w.setDisplayPercent(200,commit:true))
        precondition(w.beginObject(source:.gesture,activation:w.activation))
        w.updateObject(translation:[0.12,0.03,-0.02],rotation:simd_quatf(angle:.pi/4,axis:[0,1,0]),activation:w.activation)
        w.finishObject(activation:w.activation)
        let meshPose=ObjectPose(w.mesh.renderer.root.transform)
        let denied=await w.convert(to:.cad,replaceConfirmed:false);precondition(!denied && w.cad.bodyID==body)
        await convert(w,to:.cad)
        precondition(w.mesh.document.positions==deformed && ObjectPose(w.cad.renderer.root.transform)==meshPose)
        precondition(w.cad.measurements!.faces==9 && w.cad.measurements!.splitFaces==3)
        precondition(w.cadObject.percent>199.99 && w.cadObject.percent<200.01,"Display scale copied, not baked into mm")
        precondition(volume(w.cad.bodyID)<40_000_000 && volume(w.cad.bodyID)>15_000_000,"Never 8x CAD volume at 200%")
        let beforeVertex=await drag(w,mode:.vertex,delta:[0.01,0.015,-0.008],space:space)
        let vertexBody=w.cad.bodyID
        await action(w,.undo);precondition(w.cad.bodyID==beforeVertex)
        await action(w,.redo);precondition(w.cad.bodyID==vertexBody)
        await action(w,.cut);precondition(w.cad.hasCut && sc_body_validate(w.cad.bodyID)==0)
        await convert(w,to:.mesh)
        precondition(w.mesh.document.faces.count>6,"Variable logical topology supported")
        await convert(w,to:.cad)
        precondition(sc_body_validate(w.cad.bodyID)==0)
        await action(w,.reset)
        let box=w.cad.committedMesh!.polygonMesh!
        let pair=box.edges[0];let axis=simd_normalize(box.pointsMM[Int(pair[1])]-box.pointsMM[Int(pair[0])])
        let reference:SIMD3<Double>=abs(axis.x)<0.9 ? [1,0,0]:[0,1,0]
        let u=simd_normalize(simd_cross(axis,reference)),v=simd_cross(axis,u),deltaCAD=u*20+v*10
        let expected=box.pointsMM.enumerated().map { pair.contains(UInt32($0.offset)) ? $0.element+deltaCAD:$0.element }
        let beforeEdge=await drag(w,mode:.edge,delta:CADCoordinateConversion.positionMM(deltaCAD),space:space)
        precondition(w.cad.measurements!.faces==6,"Tilted planar faces stay polygons")
        let actual=w.cad.committedMesh!.polygonMesh!.pointsMM
        precondition(expected.allSatisfy { p in actual.contains { simd_length($0-p)<0.0001 } },"Selected CAD edge endpoints move; other corners stay fixed")
        await action(w,.undo);precondition(w.cad.bodyID==beforeEdge)
        await action(w,.redo)
        w.setCADSelectionMode(.face)
        let face=cadHandle(w,.face),target=face.components[CADTopologyTarget.self]!
        let normal=w.cad.committedMesh!.topology.first { $0.selection==target.selection }!.normal
        precondition(w.beginCADInput(entity:face,at:.zero,activation:w.activation))
        w.finishCADInput(at:normal*0.003,activation:w.activation,entity:face);await w.cad.waitForPreview()
        precondition(sc_body_validate(w.cad.bodyID)==0 && w.cad.errorMessage==nil)
        await action(w,.cut)
        // Impossible move through the box: rendering may preview it, but the body/history must roll back.
        await action(w,.reset);w.setCADSelectionMode(.vertex)
        let invalidHandle=cadHandle(w,.vertex),validBody=w.cad.bodyID,validRevision=w.cad.revision
        precondition(w.beginCADInput(entity:invalidHandle,at:.zero,activation:w.activation))
        let invalidMesh=w.cad.committedMesh!.polygonMesh!
        let adjacent=invalidMesh.edges.first { $0.contains(0) }!.first { $0 != 0 }!
        let collapse=CADCoordinateConversion.positionMM(invalidMesh.pointsMM[Int(adjacent)])-CADCoordinateConversion.positionMM(invalidMesh.pointsMM[0])
        w.finishCADInput(at:collapse,activation:w.activation,entity:invalidHandle);await w.cad.waitForPreview()
        precondition(w.cad.bodyID==validBody && w.cad.revision==validRevision && w.cad.errorMessage != nil,"Invalid reconstruction rejected; no preview-only result retained")
        precondition(w.beginCADInput(entity:invalidHandle,at:.zero,activation:w.activation))
        w.updateCADInput(to:[0.01,0.01,0.01],activation:w.activation,entity:invalidHandle)
        w.cad.cancelDrag();await w.cad.waitForPreview();precondition(w.cad.bodyID==validBody)
        // Invalid source mesh leaves the existing CAD session intact.
        precondition(w.setMode(.mesh))
        let cube=CubePrimitive.make()
        let open=MeshDocument(vertices:cube.vertices,edges:cube.edges,faces:Array(cube.faces.dropLast()))
        try w.mesh.replaceDocument(open)
        let failed=await w.convert(to:.cad,replaceConfirmed:true)
        precondition(!failed && w.activeMode == .mesh && w.cad.bodyID==validBody && w.errorMessage != nil)
        await w.cad.service.shutdown()
        let stats=try await w.cad.service.registryStats();precondition(stats.0==0 && stats.1==0)
        print("PASS: Mesh Cube/deformed Cube → CAD, CAD → variable-topology Mesh → CAD; preserved polygon boundaries and display pose")
        print("PASS: confirmed destination replacement, source retention, conversion Undo/Redo, rotated 200% hybrid Vertex/Edge edits")
        print("PASS: post-conversion Boolean/Face Offset, invalid-source and invalid-drag rollback, cancellation, zero leaked handles")
    }
}
