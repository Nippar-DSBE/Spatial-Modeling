// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT
//! Planar polygon / exact B-rep adapter. No display tessellation is used as authority.
//! The caller must additionally run the application's global boundary-intersection guard.
use std::collections::BTreeMap;
use solidcore_record::brep::{self as r,Brep,Curve,Curve2,Edge,Face,Loop,OrientedEdge,OrientedFace,Region,Shell,Surface,Vertex};
use solidcore_ops::Body;
pub type Point=[f64;3];
pub const TOLERANCE_MM:f64=1e-4;
#[derive(Clone,Debug)] pub struct PolygonMesh {pub points:Vec<Point>,pub edges:Vec<[u32;2]>,pub faces:Vec<Vec<u32>>}
pub struct Converted {pub body:Body,pub split_faces:usize,pub welded_vertices:usize}
fn sub(a:Point,b:Point)->Point{[a[0]-b[0],a[1]-b[1],a[2]-b[2]]}
fn dot(a:Point,b:Point)->f64{a[0]*b[0]+a[1]*b[1]+a[2]*b[2]}
fn cross(a:Point,b:Point)->Point{[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]}
fn norm(v:Point)->f64{dot(v,v).sqrt()}
fn unit(v:Point)->Result<Point,String>{let n=norm(v);if n<=TOLERANCE_MM{return Err("degenerate plane or edge".into())}Ok(v.map(|x|x/n))}
fn frame(points:&[Point],cycle:&[u32])->Result<(Point,Point,Point,Point),String>{
 if cycle.len()<3{return Err("face needs at least three vertices".into())}
 let o=points[cycle[0] as usize];let u=unit(sub(points[cycle[1] as usize],o))?;
 let mut n=[0.;3];
 for i in 0..cycle.len(){let a=sub(points[cycle[i] as usize],o);let b=sub(points[cycle[(i+1)%cycle.len()] as usize],o);let c=cross(a,b);for k in 0..3{n[k]+=c[k]}}
 let n=unit(n)?;let v=unit(cross(n,u))?;let u=unit(cross(v,n))?;Ok((o,u,v,n))
}
fn area2(a:[f64;2],b:[f64;2],c:[f64;2])->f64{(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])}
/// Deterministic ear clipping of one B-rep boundary; starts at corner 1 (a quad keeps diagonal 0-2).
pub fn triangulate(points:&[Point],cycle:&[u32])->Result<Vec<Vec<u32>>,String>{
 let (o,u,v,_)=frame(points,cycle)?;
 let uv=|id:u32|{let p=sub(points[id as usize],o);[dot(p,u),dot(p,v)]};
 let mut left=cycle.to_vec();let mut result=Vec::new();
 while left.len()>3{
  let mut ear=None;
  for step in 0..left.len(){let i=(step+1)%left.len();let prev=(i+left.len()-1)%left.len();let next=(i+1)%left.len();let a=uv(left[prev]);let b=uv(left[i]);let c=uv(left[next]);
   if area2(a,b,c)<=TOLERANCE_MM*TOLERANCE_MM{continue}
   let contains=left.iter().enumerate().any(|(j,&id)|j!=prev&&j!=i&&j!=next&&{let p=uv(id);area2(a,b,p)>=-1e-10&&area2(b,c,p)>=-1e-10&&area2(c,a,p)>=-1e-10});
   if !contains{ear=Some((i,vec![left[prev],left[i],left[next]]));break}
  }
  let Some((i,triangle))=ear else{return Err("face loop crosses, is degenerate, or cannot be triangulated".into())};result.push(triangle);left.remove(i);
 }
 result.push(left);Ok(result)
}
/// Export actual canonical CAD vertices/edges/face loops. No tessellation diagonals.
pub fn from_record(record:&Brep)->Result<PolygonMesh,String>{
 if record.regions.len()!=2||record.shells.len()!=1{return Err("conversion supports one closed shell without cavities".into())}
 let Shell::Faces{faces:uses,wires}=&record.shells[0] else{return Err("not a face shell".into())};
 if !wires.is_empty()||record.faces.iter().any(|f|!matches!(f.surface,Surface::Plane{..})||f.nurbs.is_some())||record.edges.iter().any(|e|!matches!(e.curve,Curve::Line{..})||e.nurbs.is_some()) {return Err("conversion requires planar faces and straight edges".into())}
 let mut faces=Vec::new();
 for (id,f) in record.faces.iter().enumerate(){
  if f.loops.len()!=1{return Err("faces with holes are outside the initial conversion scope".into())}
  let Loop::Edges{edges}=&f.loops[0] else{return Err("vertex loop unsupported".into())};
  let mut cycle=edges.iter().map(|e|{let pair=record.edges[e.edge as usize].vertices;if e.forward{pair[0]}else{pair[1]}}).collect::<Vec<_>>();
  let direction=uses.iter().find(|f|f.face as usize==id).ok_or("unused face")?.forward;
  if !direction{cycle.reverse()}
  faces.push(cycle);
 }
 Ok(PolygonMesh{points:record.vertices.iter().map(|v|v.point).collect(),edges:record.edges.iter().map(|e|e.vertices).collect(),faces})
}
/// Generate exact planes, lines, UV trims and shared topology. Planar n-gons stay n-gons.
pub fn to_body(input:&PolygonMesh)->Result<Converted,String>{
 if input.points.len()<4||input.points.len()>256||input.faces.len()<4||input.faces.len()>512{return Err("polyhedron conversion budget: 4...256 vertices, 4...512 faces".into())}
 if input.points.iter().flatten().any(|p|!p.is_finite()||p.abs()>1e6){return Err("nonfinite or out-of-range CAD point".into())}
 let mut points:Vec<Point>=Vec::new();let mut weld=Vec::new();
 for &p in &input.points{
  let id=points.iter().position(|&q|norm(sub(p,q))<=TOLERANCE_MM).unwrap_or_else(||{points.push(p);points.len()-1});weld.push(id as u32);
 }
 let mut cycles=Vec::new();let mut split_faces=0;
 for face in &input.faces{
  if face.len()<3||face.len()>128||face.iter().any(|&i|i as usize>=input.points.len()){return Err("invalid polygon index/count".into())}
  let cycle=face.iter().map(|&id|weld[id as usize]).collect::<Vec<_>>();
  if cycle.iter().copied().collect::<std::collections::BTreeSet<_>>().len()!=cycle.len(){return Err("welding collapses a face boundary".into())}
  let (o,_,_,n)=frame(&points,&cycle)?;
  if cycle.iter().all(|&i|dot(sub(points[i as usize],o),n).abs()<=TOLERANCE_MM){
   // Validate concave/simple loops as well; retain the polygon itself.
   triangulate(&points,&cycle)?;cycles.push(cycle);
  }else{split_faces+=1;cycles.extend(triangulate(&points,&cycle)?)}
 }
 let mut record=Brep{version:r::VERSION,tolerance:TOLERANCE_MM,regions:vec![Region{shells:vec![0],void:false},Region{shells:vec![0],void:false}],shells:vec![],faces:vec![],edges:vec![],vertices:points.iter().map(|&point|Vertex{point,tolerance:TOLERANCE_MM}).collect()};
 let mut pairs=BTreeMap::<(u32,u32),usize>::new();let mut uses=Vec::new();
 for cycle in cycles{
  let (o,u,v,_)=frame(&points,&cycle)?;let uv=|id:u32|{let p=sub(points[id as usize],o);[dot(p,u),dot(p,v)]};
  let mut boundary=Vec::new();
  for i in 0..cycle.len(){let a=cycle[i];let b=cycle[(i+1)%cycle.len()];if norm(sub(points[a as usize],points[b as usize]))<=TOLERANCE_MM{return Err("zero-length edge".into())}
   let key=(a.min(b),a.max(b));let id=if let Some(&id)=pairs.get(&key){id}else{let id=record.edges.len();pairs.insert(key,id);record.edges.push(Edge{curve:Curve::Line{start:points[a as usize],end:points[b as usize]},nurbs:None,interval:[0.,1.],vertices:[a,b],tolerance:TOLERANCE_MM,uses:vec![]});id};
   let pair=record.edges[id].vertices;boundary.push(OrientedEdge{edge:id as u32,forward:pair[0]==a,pcurve:Curve2::Spline{knots:vec![0.,0.,1.,1.],points:vec![uv(pair[0]),uv(pair[1])]}});
  }
  let mut low=[f64::INFINITY;2];let mut high=[f64::NEG_INFINITY;2];for &id in &cycle{let p=uv(id);for k in 0..2{low[k]=low[k].min(p[k]);high[k]=high[k].max(p[k])}}
  uses.push(OrientedFace{face:record.faces.len() as u32,forward:true});
  record.faces.push(Face{surface:Surface::Plane{origin:o,u_axis:u,v_axis:v},nurbs:None,domain:[[low[0]-TOLERANCE_MM,high[0]+TOLERANCE_MM],[low[1]-TOLERANCE_MM,high[1]+TOLERANCE_MM]],loops:vec![Loop::Edges{edges:boundary}]});
 }
 record.shells.push(Shell::Faces{faces:uses,wires:vec![]});
 // Canonicalization computes each edge's radial uses in the record walk.
 let record=record.canonical().map_err(|e|format!("canonical topology: {e:?}"))?.brep;
 if record.edges.iter().any(|e|e.uses.len()!=2){return Err("shell is open or non-manifold".into())}
 record.validate().map_err(|e|format!("record validation: {e:?}"))?;
 let (body,_)=Body::from_record(&record,false).map_err(|e|format!("SolidCore B-rep construction: {e}"))?;
 body.check_solid().map_err(|e|format!("closed outward solid: {e}"))?;
 let body=if input.faces.iter().all(|f|f.len()==3){
  let (_,order)=body.to_record().map_err(|e|format!("coplanar merge order: {e}"))?;
  solidcore_ops::stitch::merge_faces(body,&order,&[]).map_err(|e|format!("coplanar merge: {e}"))?
 }else{body};
 body.check_solid().map_err(|e|format!("merged solid: {e}"))?;
 let check=body.check(solidcore_ops::check::CheckLevel::Geometry).map_err(|e|format!("geometry check: {e}"))?;
 if !check.is_valid(){return Err(format!("invalid geometry: {check}"))}
 Ok(Converted{body,split_faces,welded_vertices:input.points.len()-points.len()})
}
