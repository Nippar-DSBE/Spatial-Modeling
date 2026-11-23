//! Phase 1 ABI. Owned bodies stay on an 8 MiB Rust worker. Handles are never reused.
//! Geometry is exclusively SolidCore. Failed operations never replace their operands.
#![deny(unsafe_op_in_unsafe_fn)]
use std::{cell::RefCell, collections::{BTreeMap, BTreeSet}, panic::{catch_unwind, AssertUnwindSafe}, sync::{OnceLock,mpsc}, time::Instant};
use solidcore_ops::{Body, BooleanOp};
mod planar_guard;

#[repr(C)] #[derive(Clone,Copy,Default,Debug)]
pub struct SCVertex {pub x:f32,pub y:f32,pub z:f32,pub nx:f32,pub ny:f32,pub nz:f32}
#[repr(C)] #[derive(Clone,Copy,Default,Debug)]
pub struct SCMeshInfo {pub vertex_count:u64,pub triangle_count:u64,pub face_count:u64,pub buffer_bytes:u64,pub tessellation_ns:u64,pub body_handle:u64,pub topology_count:u64}
#[repr(C)] #[derive(Clone,Copy,Default,Debug)]
pub struct SCPoint {pub x:f64,pub y:f64,pub z:f64}
#[repr(C)] #[derive(Clone,Copy,Default,Debug)]
pub struct SCEdge {pub a:u32,pub b:u32}
#[repr(C)] #[derive(Clone,Copy,Default,Debug)]
pub struct SCPolygonInfo {pub vertex_count:u64,pub edge_count:u64,pub face_count:u64,pub index_count:u64}
#[repr(C)] #[derive(Clone,Copy,Default,Debug)]
pub struct SCRegistryStats {pub live_bodies:u64,pub live_meshes:u64,pub mesh_bytes:u64}
#[repr(C)] #[derive(Clone,Copy,Default,Debug)]
pub struct SCTopology { pub id:u32,pub kind:u32,pub editable:u32,pub reserved:u32,pub x:f64,pub y:f64,pub z:f64,pub nx:f64,pub ny:f64,pub nz:f64 }
struct Mesh {info:SCMeshInfo,vertices:Vec<SCVertex>,indices:Vec<u32>,faces:Vec<u32>,topology:Vec<SCTopology>,polygon:Option<spatial_mesh_cad::PolygonMesh>}
#[derive(Default)]
struct Registry {next:u64,bodies:BTreeMap<u64,Body>,meshes:BTreeMap<u64,Mesh>,configured:bool}
impl Registry {
 fn init(&mut self)->Result<(),String> {
  if !self.configured {
   let fixes=solidcore::kernel::UpstreamFixes::all();
   solidcore_ops::session::set_fixes(fixes.flags().filter(|(_,on)| *on).map(|(name,_)|name)).map_err(|e|format!("kernel configuration: {e:?}"))?;
   self.configured=true;
  } Ok(())
 }
 fn id(&mut self)->Result<u64,String> {self.next=self.next.checked_add(1).ok_or("handle space exhausted")?;Ok(self.next)}
 fn body(&self,id:u64)->Result<&Body,String>{self.bodies.get(&id).ok_or_else(||format!("invalid or released body {id}"))}
}
type Job=Box<dyn FnOnce(&mut Registry)+Send>;
static WORKER:OnceLock<Result<mpsc::Sender<Job>,String>>=OnceLock::new();
fn job<T:Send+'static>(f:impl FnOnce(&mut Registry)->Result<T,String>+Send+'static)->Result<T,String> {
 let worker=WORKER.get_or_init(|| {
  let (tx,rx)=mpsc::channel::<Job>();
  std::thread::Builder::new().name("solidcore-probe".into()).stack_size(8<<20).spawn(move|| {
   let mut state=Registry::default();
   for task in rx {task(&mut state);}
  }).map_err(|e|format!("worker: {e}"))?;
  Ok(tx)
 });
 let sender=worker.as_ref().map_err(Clone::clone)?;
 let (tx,rx)=mpsc::sync_channel(1);
 sender.send(Box::new(move |r| {
  let result=catch_unwind(AssertUnwindSafe(||{r.init()?;f(r)})).unwrap_or_else(|_|Err("panic contained at SolidCore worker boundary".into()));
  let _=tx.send(result);
 })).map_err(|_|"kernel worker unavailable")?;
 rx.recv().map_err(|_|"kernel worker stopped")?
}
thread_local!{static ERROR:RefCell<Vec<u8>>=const{RefCell::new(Vec::new())};}
fn status(f:impl FnOnce()->Result<(),String>)->i32 {
 let result=catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|_|Err("panic contained at C ABI boundary".into()));
 match result {Ok(())=>{ERROR.with(|e|e.borrow_mut().clear());0},Err(msg)=>{ERROR.with(|e|*e.borrow_mut()=msg.replace('\0'," ").into_bytes());1}}
}
fn elapsed(start:Instant)->u64 {start.elapsed().as_nanos().min(u64::MAX as u128) as u64}
fn check_ptr<T>(ptr:*mut T)->Result<(),String>{if ptr.is_null(){Err("null output pointer".into())}else if (ptr as usize)%std::mem::align_of::<T>()!=0 {Err("unaligned output pointer".into())}else{Ok(())}}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_box(x:f64,y:f64,z:f64,sx:f64,sy:f64,sz:f64,out:*mut u64,time:*mut u64)->i32 {status(|| {
 check_ptr(out)?;check_ptr(time)?;
 let (id,ns)=job(move|r| {let start=Instant::now();let body=solidcore_ops::make_box([x,y,z],[sx,sy,sz]).map_err(|e|format!("box: {e}"))?;let ns=elapsed(start);let id=r.id()?;r.bodies.insert(id,body);Ok((id,ns))})?;
 unsafe{out.write(id);time.write(ns)};Ok(())
})}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_difference(a:u64,b:u64,out:*mut u64,time:*mut u64)->i32 {status(|| {
 check_ptr(out)?;check_ptr(time)?;
 let (id,ns)=job(move|r| {
  let start=Instant::now();
  let ca=r.body(a)?.copy().map_err(|e|format!("copy target: {e}"))?;
  let cb=r.body(b)?.copy().map_err(|e|format!("copy tool: {e}"))?;
  let body=solidcore_ops::boolean::boolean(ca,cb,BooleanOp::Subtract).map_err(|e|format!("difference: {e}"))?.ok_or("difference is empty; current body preserved")?;
  let counts=body.counts().map_err(|e|format!("result validation: {e}"))?;
  if counts[0]==0{return Err("result has no faces".into())}
  let ns=elapsed(start);let id=r.id()?;r.bodies.insert(id,body);Ok((id,ns))
 })?;unsafe{out.write(id);time.write(ns)};Ok(())
})}
/// A command against one immutable body/record snapshot; never edits the source.
/// Copy-with-order maps the picked record index to the copy's actual kernel FaceId.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_offset_face(source:u64,face:u32,distance:f64,out:*mut u64,time:*mut u64)->i32 {status(|| {
 check_ptr(out)?;check_ptr(time)?;
 if !distance.is_finite()||distance.abs()<0.01||distance.abs()>500.0{return Err("offset range is 0.01...500 mm (signed)".into())}
 let (id,ns)=job(move|r| {
  let start=Instant::now();let original=r.body(source)?;
  let (record,order)=original.to_record().map_err(|e|format!("offset record: {e}"))?;
  if face as usize>=record.faces.len(){return Err("stale or invalid face index".into())}
  if !planar_linear(&record){return Err("Phase 3 supports planar faces and straight edges only".into())}
  let (candidate,mapped)=original.copy_with_order(&order).map_err(|e|format!("copy with order: {e}"))?;
  solidcore_ops::offset_faces(&candidate,&mapped,&[face as usize],distance).map_err(|e|format!("face offset refused: {e}"))?;
  validate_solid(&candidate)?;
  let ns=elapsed(start);let id=r.id()?;r.bodies.insert(id,candidate);Ok((id,ns))
 })?;unsafe{out.write(id);time.write(ns)};Ok(())
})}
fn planar_linear(record:&solidcore_record::brep::Brep)->bool {
 record.faces.iter().all(|f|matches!(f.surface,solidcore_record::brep::Surface::Plane{..})&&f.nurbs.is_none())&&
 record.edges.iter().all(|e|matches!(e.curve,solidcore_record::brep::Curve::Line{..})&&e.nurbs.is_none())
}
fn validate_solid(body:&Body)->Result<(),String> {
 body.check_solid().map_err(|e|format!("closed outward solid validation: {e}"))?;
 let check=body.check(solidcore_ops::check::CheckLevel::Geometry).map_err(|e|format!("geometry check: {e}"))?;
 if !check.is_valid(){return Err(format!("invalid solid: {check}"))}
 let (record,_)=body.to_record().map_err(|e|format!("validation record: {e}"))?;
 if planar_linear(&record){planar_guard::check(&record)?}
 Ok(())
}
#[unsafe(no_mangle)]
pub extern "C" fn sc_body_validate(body:u64)->i32 {status(||job(move|r|validate_solid(r.body(body)?)))}
/// Input geometry is CAD-local f64 mm/Z-up. Display transforms never enter this ABI.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_body_from_polygons(points:*const SCPoint,vc:usize,offsets:*const u32,fc:usize,indices:*const u32,ic:usize,out:*mut u64,time:*mut u64,splits:*mut u64)->i32 {status(|| {
 check_ptr(points.cast_mut())?;check_ptr(offsets.cast_mut())?;check_ptr(indices.cast_mut())?;check_ptr(out)?;check_ptr(time)?;check_ptr(splits)?;
 if !(4..=256).contains(&vc)||!(4..=512).contains(&fc)||ic>16384{return Err("polygon input budget exceeded".into())}
 let pts=unsafe{std::slice::from_raw_parts(points,vc)}.iter().map(|p|[p.x,p.y,p.z]).collect::<Vec<_>>();
 let offsets=unsafe{std::slice::from_raw_parts(offsets,fc+1)}.to_vec();let indices=unsafe{std::slice::from_raw_parts(indices,ic)}.to_vec();
 if offsets[0]!=0||offsets[fc] as usize!=ic||offsets.windows(2).any(|w|w[0]>w[1]){return Err("invalid polygon offsets".into())}
 let faces=offsets.windows(2).map(|w|indices[w[0] as usize..w[1] as usize].to_vec()).collect();
 let (id,ns,split)=job(move|r|{let start=Instant::now();let made=spatial_mesh_cad::to_body(&spatial_mesh_cad::PolygonMesh{points:pts,edges:vec![],faces})?;
  validate_solid(&made.body)?;let ns=elapsed(start);let id=r.id()?;r.bodies.insert(id,made.body);Ok((id,ns,made.split_faces as u64))})?;
 unsafe{out.write(id);time.write(ns);splits.write(split)};Ok(())
})}
#[unsafe(no_mangle)]
pub extern "C" fn sc_body_release(id:u64)->i32 {status(||job(move|r|r.bodies.remove(&id).map(drop).ok_or_else(||format!("invalid or released body {id}"))))}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_body_volume(id:u64,out:*mut f64)->i32{status(||{check_ptr(out)?;let v=job(move|r|r.body(id)?.volume(1e-8).map_err(|e|format!("volume: {e}")))?;unsafe{out.write(v)};Ok(())})}
static TESS_POOL:OnceLock<Result<rayon::ThreadPool,String>>=OnceLock::new();
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_tessellate(body_id:u64,chord:f64,out:*mut u64)->i32 {status(|| {
 check_ptr(out)?;
 if !chord.is_finite()||chord<0.01||chord>10.0{return Err("chord must be 0.01...10 mm".into())}
 let id=job(move|r| {
  let start=Instant::now();let (record,_)=r.body(body_id)?.to_record().map_err(|e|format!("record: {e}"))?;
  if record.faces.is_empty()||record.faces.len()>512{return Err("face budget exceeded".into())}
  let mut lo=[f64::INFINITY;3];let mut hi=[f64::NEG_INFINITY;3];
  for v in &record.vertices {for axis in 0..3{lo[axis]=lo[axis].min(v.point[axis]);hi[axis]=hi[axis].max(v.point[axis]);}}
  let size=((hi[0]-lo[0]).powi(2)+(hi[1]-lo[1]).powi(2)+(hi[2]-lo[2]).powi(2)).sqrt();
  if !size.is_finite()||size<=0.0{return Err("invalid body bounds".into())}
  let pool=TESS_POOL.get_or_init(||rayon::ThreadPoolBuilder::new().num_threads(2).stack_size(8<<20).build().map_err(|e|e.to_string())).as_ref().map_err(Clone::clone)?;
  let (plan,stats)=pool.install(||solidcore_tess::plan(&record,&solidcore_tess::MeshTolerance::display(chord),size)).map_err(|e|format!("tessellation: {e}"))?;
  if !stats.unmeshed.is_empty()||!stats.lenient.is_empty(){return Err("tessellator refused one or more CAD faces".into())}
  let (mesh,refused)=plan.evaluate();
  if !refused.is_empty(){return Err("surface evaluation refused faces".into())}
  let n=mesh.positions.len();let t=mesh.triangles.len();
  if n==0||n>1_000_000||t==0||t>1_000_000||mesh.normals.len()!=n||mesh.tri_face.len()!=t{return Err("invalid tessellation sizes".into())}
  let mut vertices=Vec::with_capacity(n);
  for (p,n) in mesh.positions.iter().zip(&mesh.normals){
   let a=[p.x as f32,p.y as f32,p.z as f32,n.x as f32,n.y as f32,n.z as f32];
   if a.iter().any(|v|!v.is_finite())||a[3]*a[3]+a[4]*a[4]+a[5]*a[5]<1e-10{return Err("nonfinite vertex or invalid normal".into())}
   vertices.push(SCVertex{x:a[0],y:a[1],z:a[2],nx:a[3],ny:a[4],nz:a[5]});
  }
  if mesh.triangles.iter().flatten().any(|&i|i as usize>=vertices.len())||mesh.tri_face.iter().any(|&f|f as usize>=record.faces.len()){return Err("invalid triangle or face index".into())}
  let faces_seen:BTreeSet<_>=mesh.tri_face.iter().copied().collect();
  if faces_seen.len()!=record.faces.len(){return Err("not every CAD face has display triangles".into())}
  let editable=planar_linear(&record);
  let polygon=spatial_mesh_cad::from_record(&record).ok();
  let mut topology=Vec::new();
  for (id,v) in record.vertices.iter().enumerate(){topology.push(SCTopology{id:id as u32,kind:0,editable:u32::from(polygon.is_some()),x:v.point[0],y:v.point[1],z:v.point[2],..Default::default()});}
  for (id,e) in record.edges.iter().enumerate(){
   let a=record.vertices[e.vertices[0] as usize].point;let b=record.vertices[e.vertices[1] as usize].point;
   topology.push(SCTopology{id:id as u32,kind:1,editable:u32::from(polygon.is_some()),x:(a[0]+b[0])*0.5,y:(a[1]+b[1])*0.5,z:(a[2]+b[2])*0.5,..Default::default()});
  }
  for id in 0..record.faces.len(){
   // A point inside an actual face triangle, including concave/holed cut faces.
   let mut best=0.0;let mut center=[0.;3];let mut normal=[0.;3];
   for (t,&f) in mesh.triangles.iter().zip(&mesh.tri_face){if f as usize!=id{continue}
    let a=mesh.positions[t[0] as usize];let b=mesh.positions[t[1] as usize];let c=mesh.positions[t[2] as usize];
    let u=b-a;let v=c-a;let cross=[u.y*v.z-u.z*v.y,u.z*v.x-u.x*v.z,u.x*v.y-u.y*v.x];let area=cross.iter().map(|x|x*x).sum::<f64>();
    if area>best{best=area;center=[(a.x+b.x+c.x)/3.,(a.y+b.y+c.y)/3.,(a.z+b.z+c.z)/3.];let n=mesh.normals[t[0] as usize];normal=[n.x,n.y,n.z];}
   }
   topology.push(SCTopology{id:id as u32,kind:2,editable:u32::from(editable),x:center[0],y:center[1],z:center[2],nx:normal[0],ny:normal[1],nz:normal[2],reserved:0});
  }
  let indices=mesh.triangles.into_iter().flatten().collect::<Vec<_>>();
  let faces=mesh.tri_face;let id=r.id()?;
  let bytes=vertices.len()*std::mem::size_of::<SCVertex>()+indices.len()*4+faces.len()*4+topology.len()*std::mem::size_of::<SCTopology>()+polygon.as_ref().map_or(0,|p|p.points.len()*24+p.edges.len()*8+p.faces.iter().map(|f|f.len()*4).sum::<usize>());
  let info=SCMeshInfo{vertex_count:n as u64,triangle_count:t as u64,face_count:record.faces.len() as u64,buffer_bytes:bytes as u64,tessellation_ns:elapsed(start),body_handle:body_id,topology_count:topology.len() as u64};
  r.meshes.insert(id,Mesh{info,vertices,indices,faces,topology,polygon});Ok(id)
 })?;unsafe{out.write(id)};Ok(())
})}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_mesh_info(id:u64,out:*mut SCMeshInfo)->i32{status(||{check_ptr(out)?;let info=job(move|r|r.meshes.get(&id).map(|m|m.info).ok_or("invalid or released mesh".into()))?;unsafe{out.write(info)};Ok(())})}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_mesh_copy(id:u64,vertices:*mut SCVertex,vc:usize,indices:*mut u32,ic:usize,faces:*mut u32,fc:usize)->i32{status(|| {
 check_ptr(vertices)?;check_ptr(indices)?;check_ptr(faces)?;
 // Addresses cross the owned worker as integers; the caller is blocked until copying ends.
 // Contract: non-overlapping writable arrays remain valid for the duration of this call.
 let (vp,ip,fp)=(vertices as usize,indices as usize,faces as usize);
 job(move|r|{let mesh=r.meshes.get(&id).ok_or("invalid or released mesh")?;
  if vc<mesh.vertices.len()||ic<mesh.indices.len()||fc<mesh.faces.len(){return Err("destination capacity too small".into())}
  unsafe{std::ptr::copy_nonoverlapping(mesh.vertices.as_ptr(),vp as *mut SCVertex,mesh.vertices.len());std::ptr::copy_nonoverlapping(mesh.indices.as_ptr(),ip as *mut u32,mesh.indices.len());std::ptr::copy_nonoverlapping(mesh.faces.as_ptr(),fp as *mut u32,mesh.faces.len());}Ok(())
 })
})}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_mesh_topology_copy(id:u64,out:*mut SCTopology,capacity:usize)->i32 {status(|| {
 check_ptr(out)?;let address=out as usize;
 job(move|r|{let m=r.meshes.get(&id).ok_or("invalid mesh")?;if capacity<m.topology.len(){return Err("topology capacity too small".into())}
 unsafe{std::ptr::copy_nonoverlapping(m.topology.as_ptr(),address as *mut SCTopology,m.topology.len())};Ok(())})
})}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_mesh_polygon_info(id:u64,out:*mut SCPolygonInfo)->i32 {status(|| {
 check_ptr(out)?;let info=job(move|r|{let p=r.meshes.get(&id).and_then(|m|m.polygon.as_ref()).ok_or("CAD body is outside planar polygon conversion scope")?;
 Ok(SCPolygonInfo{vertex_count:p.points.len() as u64,edge_count:p.edges.len() as u64,face_count:p.faces.len() as u64,index_count:p.faces.iter().map(|f|f.len() as u64).sum()})})?;
 unsafe{out.write(info)};Ok(())
})}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_mesh_polygon_copy(id:u64,points:*mut SCPoint,vc:usize,edges:*mut SCEdge,ec:usize,offsets:*mut u32,oc:usize,indices:*mut u32,ic:usize)->i32 {status(|| {
 check_ptr(points)?;check_ptr(edges)?;check_ptr(offsets)?;check_ptr(indices)?;
 let (pp,ep,op,ip)=(points as usize,edges as usize,offsets as usize,indices as usize);
 job(move|r|{let p=r.meshes.get(&id).and_then(|m|m.polygon.as_ref()).ok_or("no planar topology")?;
 if vc<p.points.len()||ec<p.edges.len()||oc<p.faces.len()+1||ic<p.faces.iter().map(|f|f.len()).sum::<usize>(){return Err("polygon output capacity too small".into())}
 let mut offset=0;
 unsafe{
  for (i,v) in p.points.iter().enumerate(){(pp as *mut SCPoint).add(i).write(SCPoint{x:v[0],y:v[1],z:v[2]});}
  for (i,e) in p.edges.iter().enumerate(){(ep as *mut SCEdge).add(i).write(SCEdge{a:e[0],b:e[1]});}
  for (i,f) in p.faces.iter().enumerate(){(op as *mut u32).add(i).write(offset as u32);std::ptr::copy_nonoverlapping(f.as_ptr(),(ip as *mut u32).add(offset),f.len());offset+=f.len();}
  (op as *mut u32).add(p.faces.len()).write(offset as u32);
 }Ok(())})
})}
#[unsafe(no_mangle)]
pub extern "C" fn sc_mesh_release(id:u64)->i32{status(||job(move|r|r.meshes.remove(&id).map(drop).ok_or("invalid or released mesh".into())))}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_registry_stats(out:*mut SCRegistryStats)->i32{status(||{check_ptr(out)?;let s=job(|r|Ok(SCRegistryStats{live_bodies:r.bodies.len() as u64,live_meshes:r.meshes.len() as u64,mesh_bytes:r.meshes.values().map(|m|m.info.buffer_bytes).sum()}))?;unsafe{out.write(s)};Ok(())})}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_error_copy(out:*mut std::ffi::c_char,capacity:usize)->usize {
 catch_unwind(AssertUnwindSafe(||ERROR.with(|e|{let e=e.borrow();if !out.is_null()&&capacity>0{let n=e.len().min(capacity-1);unsafe{std::ptr::copy_nonoverlapping(e.as_ptr(),out.cast(),n);out.add(n).write(0);}}e.len()+1}))).unwrap_or(0)
}

#[cfg(test)] mod tests {
 use super::*;
 fn ok(code:i32){if code!=0{let mut b=[0i8;1024];unsafe{sc_error_copy(b.as_mut_ptr(),b.len());}panic!("{}",unsafe{std::ffi::CStr::from_ptr(b.as_ptr())}.to_string_lossy());}}
 fn make(o:[f64;3],s:[f64;3])->u64{let mut id=0;let mut ns=0;ok(unsafe{sc_box(o[0],o[1],o[2],s[0],s[1],s[2],&mut id,&mut ns)});id}
 fn export(body:u64)->(Vec<SCPoint>,Vec<SCEdge>,Vec<u32>,Vec<u32>){
  let mut mesh=0;ok(unsafe{sc_tessellate(body,0.5,&mut mesh)});let mut info=SCPolygonInfo::default();ok(unsafe{sc_mesh_polygon_info(mesh,&mut info)});
  let mut points=vec![SCPoint::default();info.vertex_count as usize];let mut edges=vec![SCEdge::default();info.edge_count as usize];let mut offsets=vec![0;info.face_count as usize+1];let mut indices=vec![0;info.index_count as usize];
  ok(unsafe{sc_mesh_polygon_copy(mesh,points.as_mut_ptr(),points.len(),edges.as_mut_ptr(),edges.len(),offsets.as_mut_ptr(),offsets.len(),indices.as_mut_ptr(),indices.len())});ok(sc_mesh_release(mesh));(points,edges,offsets,indices)
 }
 fn convert(points:&[SCPoint],offsets:&[u32],indices:&[u32])->(i32,u64,u64){let mut body=0;let mut ns=0;let mut splits=0;
  let status=unsafe{sc_body_from_polygons(points.as_ptr(),points.len(),offsets.as_ptr(),offsets.len()-1,indices.as_ptr(),indices.len(),&mut body,&mut ns,&mut splits)};
  if status==0{println!("conversion vertices={} faces={} split_faces={splits} ms={:.3}",points.len(),offsets.len()-1,ns as f64/1e6)}
  (status,body,splits)
 }
 fn conversion_cases(){
  let original=make([-150.;3],[300.;3]);let (points,edges,offsets,indices)=export(original);
  assert_eq!((points.len(),edges.len(),offsets.len()-1),(8,12,6));
  let (code,cube,split)=convert(&points,&offsets,&indices);ok(code);assert_eq!(split,0);ok(sc_body_validate(cube));
  let mut volume=0.;ok(unsafe{sc_body_volume(cube,&mut volume)});assert!((volume-27_000_000.).abs()<0.1);
  // Already triangulated meshes weld shared coordinates and merge coplanar CAD faces.
  let mut duplicate_points=Vec::new();let mut tri_offsets=vec![0];let mut tri_indices=Vec::new();
  for face in offsets.windows(2){let cycle=&indices[face[0] as usize..face[1] as usize];for tri in [[cycle[0],cycle[1],cycle[2]],[cycle[0],cycle[2],cycle[3]]]{
   for id in tri {tri_indices.push(duplicate_points.len() as u32);duplicate_points.push(points[id as usize]);}tri_offsets.push(tri_indices.len() as u32);
  }}
  let (code,merged,_)=convert(&duplicate_points,&tri_offsets,&tri_indices);ok(code);
  let (mp,me,mo,_)=export(merged);assert_eq!((mp.len(),me.len(),mo.len()-1),(8,12,6));ok(sc_body_release(merged));
  let mut edited=points.clone();edited[0].x+=12.;edited[0].y+=18.;edited[0].z+=24.;
  let (code,vertex,split)=convert(&edited,&offsets,&indices);ok(code);assert!(split>0);ok(sc_body_validate(vertex));
  let counts=job(move|r|r.body(vertex)?.counts().map_err(|e|e.to_string())).unwrap();assert_eq!(counts[0],9,"only nonplanar faces split; no global triangle conversion");
  let mut shifted=points.clone();for id in [edges[0].a,edges[0].b]{shifted[id as usize].x+=20.;shifted[id as usize].y+=10.;}
  let (code,edge,_)=convert(&shifted,&offsets,&indices);ok(code);ok(sc_body_validate(edge));
  for body in [cube,vertex,edge]{
   let tool=make([0.,-200.,0.],[200.;3]);let mut cut=0;let mut ns=0;ok(unsafe{sc_difference(body,tool,&mut cut,&mut ns)});ok(sc_body_validate(cut));
   let (cp,_,co,ci)=export(cut);let (code,roundtrip,_)=convert(&cp,&co,&ci);ok(code);ok(sc_body_validate(roundtrip));ok(sc_body_release(roundtrip));
   // Choose an unsplit polygon face to test a subsequent real kernel face offset.
   let face=job(move|r|{let (record,_)=r.body(body)?.to_record().map_err(|e|e.to_string())?;Ok(record.faces.iter().position(|f|matches!(&f.loops[0],solidcore_record::brep::Loop::Edges{edges} if edges.len()>=4)).unwrap() as u32)}).unwrap();
   let mut offset=0;ok(unsafe{sc_offset_face(body,face,3.,&mut offset,&mut ns)});ok(sc_body_validate(offset));
   for id in [tool,cut,offset]{ok(sc_body_release(id));}
  }
  let mut collapsed=points.clone();collapsed[0]=collapsed[1];assert_ne!(convert(&collapsed,&offsets,&indices).0,0);
  let mut open_offsets=offsets.clone();open_offsets.pop();assert_ne!(convert(&points,&open_offsets,&indices[..*open_offsets.last().unwrap() as usize]).0,0);
  for id in [original,cube,vertex,edge]{ok(sc_body_release(id));}
 }
 #[test]fn actual_cad_and_handle_safety(){
  let a=make([-150.;3],[300.;3]);let b=make([0.,-200.,0.],[200.;3]);let mut v=0.;ok(unsafe{sc_body_volume(a,&mut v)});assert!((v-27_000_000.).abs()<1.);
  let mut c=0;let mut ns=0;ok(unsafe{sc_difference(a,b,&mut c,&mut ns)});ok(unsafe{sc_body_volume(c,&mut v)});assert!((v-23_625_000.).abs()<1.);
  let mut mesh=0;ok(unsafe{sc_tessellate(c,0.5,&mut mesh)});let mut info=SCMeshInfo::default();ok(unsafe{sc_mesh_info(mesh,&mut info)});assert!(info.face_count>6);
  let mut vs=vec![SCVertex::default();info.vertex_count as usize];let mut ids=vec![0;info.triangle_count as usize*3];let mut fs=vec![0;info.triangle_count as usize];
  assert_ne!(unsafe{sc_mesh_copy(mesh,vs.as_mut_ptr(),0,ids.as_mut_ptr(),ids.len(),fs.as_mut_ptr(),fs.len())},0);
  ok(unsafe{sc_mesh_copy(mesh,vs.as_mut_ptr(),vs.len(),ids.as_mut_ptr(),ids.len(),fs.as_mut_ptr(),fs.len())});assert_eq!(fs.iter().copied().collect::<BTreeSet<_>>().len(),info.face_count as usize);
  assert_ne!(unsafe{sc_difference(999999,b,&mut c,&mut ns)},0);assert_ne!(unsafe{sc_box(0.,0.,0.,-1.,1.,1.,&mut c,&mut ns)},0);
  ok(unsafe{sc_body_volume(a,&mut v)});assert!((v-27_000_000.).abs()<1.);
  for id in [a,b,c]{ok(sc_body_release(id));assert_ne!(sc_body_release(id),0);}
  ok(sc_mesh_release(mesh));assert_ne!(sc_mesh_release(mesh),0);
  // Actual kernel offsets on all Box and post-Boolean faces, both directions.
  for cut in [false,true] {
   let base=make([-150.;3],[300.;3]);
   let source=if cut {let tool=make([0.,-200.,0.],[200.;3]);let mut result=0;let mut ns=0;ok(unsafe{sc_difference(base,tool,&mut result,&mut ns)});ok(sc_body_release(tool));result}else{base};
   ok(sc_body_validate(source));
   let mut mesh=0;ok(unsafe{sc_tessellate(source,0.5,&mut mesh)});
   let mut info=SCMeshInfo::default();ok(unsafe{sc_mesh_info(mesh,&mut info)});
   let mut top=vec![SCTopology::default();info.topology_count as usize];ok(unsafe{sc_mesh_topology_copy(mesh,top.as_mut_ptr(),top.len())});
   assert_eq!(top.iter().filter(|t|t.kind==2).count(),info.face_count as usize);
   if !cut{assert_eq!(top.len(),26);}
   let mut original=0.;ok(unsafe{sc_body_volume(source,&mut original)});
   for face in top.iter().filter(|t|t.kind==2) {
    assert_eq!(face.editable,1);
    for distance in [-25.,25.] {
     let mut result=0;let mut ns=0;
     ok(unsafe{sc_offset_face(source,face.id,distance,&mut result,&mut ns)});
     ok(sc_body_validate(result));
     let mut volume=0.;ok(unsafe{sc_body_volume(result,&mut volume)});
     assert!((volume-original)*distance>0.,"outward/inward volume direction");
     println!("offset cut={cut} face={} mm={distance} kernel_ms={:.3}",face.id,ns as f64/1e6);
     ok(sc_body_release(result));
    }
   }
   let mut result=0;let mut ns=0;
   assert_ne!(unsafe{sc_offset_face(source,0,-500.,&mut result,&mut ns)},0);
   assert_ne!(unsafe{sc_offset_face(source,999,10.,&mut result,&mut ns)},0);
   let mut retained=0.;ok(unsafe{sc_body_volume(source,&mut retained)});assert_eq!(retained,original);
   ok(sc_mesh_release(mesh));ok(sc_body_release(source));if cut{ok(sc_body_release(base));}
  }
  conversion_cases();
  let caught=job::<()>(|_|panic!("test panic"));assert!(caught.is_err());assert!(job(|_|Ok(())).is_ok());
  let mut stats=SCRegistryStats::default();ok(unsafe{sc_registry_stats(&mut stats)});assert_eq!(stats.live_bodies,0);assert_eq!(stats.live_meshes,0);
 }
}
