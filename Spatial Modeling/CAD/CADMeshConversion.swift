// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT
import Foundation
import simd
import SolidCoreProbe

/// CAD-local f64 mm/Z-up polygons, independent of display transforms and display triangles.
struct CADPolygonMesh: Codable, Sendable {
    let pointsMM: [SIMD3<Double>]
    let edges: [[UInt32]]
    let faces: [[UInt32]]

    func document() throws -> MeshDocument {
        guard pointsMM.count >= 4, pointsMM.count <= 256, faces.count >= 4, faces.count <= 512,
              edges.allSatisfy({ $0.count == 2 && $0.allSatisfy { Int($0) < pointsMM.count } }),
              faces.allSatisfy({ $0.count >= 3 && $0.allSatisfy { Int($0) < pointsMM.count } }),
              pointsMM.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw CADIntegrationError(message: "Invalid logical polygon topology.")
        }
        let boundary=Set(faces.flatMap { face in face.indices.map { i in
            [min(face[i],face[(i+1)%face.count]),max(face[i],face[(i+1)%face.count])]
        } })
        let declared=Set(edges.map { [min($0[0],$0[1]),max($0[0],$0[1])] })
        guard declared.count==edges.count, declared==boundary else { throw CADIntegrationError(message:"Logical edges must match polygon boundaries.") }
        return MeshDocument(vertices: pointsMM.enumerated().map { Vertex(id: $0.offset, position: CADCoordinateConversion.positionMM($0.element)) },
                            edges: edges.enumerated().map { Edge(id: $0.offset, vertexIDs: $0.element.map(Int.init)) },
                            faces: faces.enumerated().map { Face(id: $0.offset, vertexIDs: $0.element.map(Int.init)) })
    }
    static func from(_ document: MeshDocument) throws -> CADPolygonMesh {
        guard Set(document.vertices.map(\.id)).count == document.vertices.count else { throw CADIntegrationError(message:"Duplicate logical vertex IDs.") }
        let ids = Dictionary(uniqueKeysWithValues: document.vertices.enumerated().map { ($0.element.id,UInt32($0.offset)) })
        let faces = try document.faces.map { face in try face.vertexIDs.map { id in
            guard let index=ids[id] else { throw CADIntegrationError(message: "Unknown mesh vertex.") };return index
        } }
        let edges = try document.edges.map { edge in try edge.vertexIDs.map { id in
            guard let index=ids[id] else { throw CADIntegrationError(message: "Unknown mesh edge vertex.") };return index
        } }
        let result=CADPolygonMesh(pointsMM: document.vertices.map { CADCoordinateConversion.cadPositionMM($0.position) },edges:edges,faces:faces)
        _ = try result.document()
        return result
    }
    static func read(_ mesh: UInt64) throws -> CADPolygonMesh {
        var info=SCPolygonInfo();try checkCAD(sc_mesh_polygon_info(mesh,&info))
        guard (4...256).contains(info.vertex_count), info.edge_count > 0, info.edge_count <= 2048,
              (4...512).contains(info.face_count), info.index_count <= 16384 else { throw CADIntegrationError(message: "Logical topology exceeds conversion scope.") }
        var points=[SCPoint](repeating:SCPoint(),count:Int(info.vertex_count))
        var edges=[SCEdge](repeating:SCEdge(),count:Int(info.edge_count))
        var offsets=[UInt32](repeating:0,count:Int(info.face_count)+1)
        var indices=[UInt32](repeating:0,count:Int(info.index_count))
        try checkCAD(sc_mesh_polygon_copy(mesh,&points,points.count,&edges,edges.count,&offsets,offsets.count,&indices,indices.count))
        guard offsets.first==0, offsets.last==UInt32(indices.count),
              zip(offsets,offsets.dropFirst()).allSatisfy({ $0.0 <= $0.1 }) else { throw CADIntegrationError(message:"Invalid face offsets.") }
        let faces=zip(offsets,offsets.dropFirst()).map { Array(indices[Int($0)..<Int($1)]) }
        let result=CADPolygonMesh(pointsMM:points.map { [$0.x,$0.y,$0.z] },edges:edges.map { [$0.a,$0.b] },faces:faces)
        _ = try result.document()
        return result
    }
    func createBody() throws -> (body: UInt64, milliseconds: Double, splitFaces: Int) {
        _ = try document()
        guard faces.allSatisfy({ $0.count <= 128 }), faces.reduce(0,{ $0+$1.count }) <= 16384 else { throw CADIntegrationError(message:"Conversion polygon budget exceeded.") }
        var points=pointsMM.map { SCPoint(x:$0.x,y:$0.y,z:$0.z) }
        var offsets:[UInt32]=[0], indices:[UInt32]=[]
        for face in faces { indices.append(contentsOf:face);offsets.append(UInt32(indices.count)) }
        var body:UInt64=0, ns:UInt64=0, splits:UInt64=0
        try checkCAD(sc_body_from_polygons(&points,points.count,&offsets,faces.count,&indices,indices.count,&body,&ns,&splits))
        return (body,milliseconds(ns),Int(splits))
    }
}

/// Reuses the same MeshDocument drag/selection engine as Mesh Mode.
/// Preserve the original f64 CAD anchors and add only the edited local displacement.
struct CADHybridEdit {
    var document: MeshDocument
    let geometry: MeshGeometry
    let original: CADPolygonMesh
    let initialPositions: PositionSnapshot
    init(_ mesh: CADPolygonMesh, selection: Selection, start: SIMD3<Float>) throws {
        var document=try mesh.document();geometry=MeshGeometry(document:document)
        initialPositions=document.positions;original=mesh
        document.beginDrag(selection,at:start);self.document=document
    }
    func result() -> CADPolygonMesh {
        let positions=document.positions
        let points=original.pointsMM.enumerated().map { id,point in
            point+CADCoordinateConversion.cadPositionMM(positions[id]!-initialPositions[id]!)
        }
        return CADPolygonMesh(pointsMM:points,edges:original.edges,faces:original.faces)
    }
    func display(snapshot: CADMesh) -> CADMesh {
        let vertices=geometry.vertices(positions:document.positions).map { CADRenderVertex(position:$0.position,normal:$0.normal) }
        return CADMesh(body:snapshot.body,revision:snapshot.revision,vertices:vertices,
                       indices:vertices.indices.map(UInt32.init),triangleFaces:geometry.triangles.map { UInt32($0.faceID) },
                       topology:snapshot.topology,faceCount:snapshot.faceCount,polygonMesh:snapshot.polygonMesh)
    }
}
