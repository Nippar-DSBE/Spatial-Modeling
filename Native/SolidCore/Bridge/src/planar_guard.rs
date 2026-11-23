//! Conservative extra boundary-intersection guard for Phase 3 planar/linear solids.
//! Works on B-rep edges/loops, never on the display tessellation. Near contact is refused.
use solidcore_record::brep::{Brep,Loop,Surface};
type V=[f64;3];
fn sub(a:V,b:V)->V{[a[0]-b[0],a[1]-b[1],a[2]-b[2]]}
fn add(a:V,b:V)->V{[a[0]+b[0],a[1]+b[1],a[2]+b[2]]}
fn mul(a:V,t:f64)->V{[a[0]*t,a[1]*t,a[2]*t]}
fn dot(a:V,b:V)->f64{a[0]*b[0]+a[1]*b[1]+a[2]*b[2]}
fn cross(a:V,b:V)->V{[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]}
fn distance2(a:V,b:V)->f64{let d=sub(a,b);dot(d,d)}
fn segment_distance2(p:V,q:V,a:V,b:V)->f64{
 let u=sub(q,p);let v=sub(b,a);let w=sub(p,a);
 let aa=dot(u,u);let bb=dot(u,v);let cc=dot(v,v);let dd=dot(u,w);let ee=dot(v,w);
 if aa<1e-20||cc<1e-20{return 0.}
 let denominator=aa*cc-bb*bb;
 let mut s=if denominator>1e-20{((bb*ee-cc*dd)/denominator).clamp(0.,1.)}else{0.};
 let t=(bb*s+ee)/cc;
 let t=if t<0.{s=(-dd/aa).clamp(0.,1.);0.}else if t>1.{s=((bb-dd)/aa).clamp(0.,1.);1.}else{t};
 distance2(add(p,mul(u,s)),add(a,mul(v,t)))
}
fn p2(p:V,axis:usize)->[f64;2]{match axis{0=>[p[1],p[2]],1=>[p[0],p[2]],_=>[p[0],p[1]]}}
fn cross2(a:[f64;2],b:[f64;2])->f64{a[0]*b[1]-a[1]*b[0]}
fn sub2(a:[f64;2],b:[f64;2])->[f64;2]{[a[0]-b[0],a[1]-b[1]]}
// Even/odd across all loops includes holes. Points on the boundary are not interior.
fn inside(point:V,boundary:&[(V,V)],axis:usize,tol:f64)->bool{
 let p=p2(point,axis);let mut inside=false;
 for &(a,b) in boundary{
  let a=p2(a,axis);let b=p2(b,axis);let v=sub2(b,a);let w=sub2(p,a);let length=v[0]*v[0]+v[1]*v[1];
  if length>0.{let t=((w[0]*v[0]+w[1]*v[1])/length).clamp(0.,1.);if (w[0]-t*v[0]).powi(2)+(w[1]-t*v[1]).powi(2)<=tol*tol{return false}}
  if (a[1]>p[1])!=(b[1]>p[1])&&p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]{inside=!inside}
 }
 inside
}
pub fn check(r:&Brep)->Result<(),String>{
 let tol=r.tolerance.max(1e-5);
 if r.edges.len()>2048{return Err("planar guard edge budget exceeded".into())}
 let segments:Vec<_>=r.edges.iter().map(|e|(r.vertices[e.vertices[0] as usize].point,r.vertices[e.vertices[1] as usize].point)).collect();
 for (i,e) in r.edges.iter().enumerate(){
  for (j,f) in r.edges.iter().enumerate().skip(i+1){
   if e.vertices.iter().any(|v|f.vertices.contains(v)){continue}
   let (a,b)=segments[i];let (c,d)=segments[j];
   if segment_distance2(a,b,c,d)<=tol*tol{return Err("nonincident B-rep edges intersect or nearly touch".into())}
  }
 }
 for face in &r.faces{
  let Surface::Plane{origin,u_axis,v_axis}=face.surface else{return Err("planar guard requires planes".into())};
  let n=cross(u_axis,v_axis);let length=dot(n,n).sqrt();if length<1e-12{return Err("degenerate face plane".into())}let n=mul(n,1./length);
  let axis=(0..3).max_by(|&a,&b|n[a].abs().total_cmp(&n[b].abs())).unwrap();
  let ids:Vec<_>=face.loops.iter().flat_map(|l|match l{Loop::Edges{edges}=>edges.iter().map(|e|e.edge as usize).collect::<Vec<_>>(),_=>Vec::new()}).collect();
  let boundary:Vec<_>=ids.iter().map(|&i|segments[i]).collect();
  for (i,&(a,b)) in segments.iter().enumerate(){
   if ids.contains(&i){continue}
   let da=dot(sub(a,origin),n);let db=dot(sub(b,origin),n);
   if da.abs()<=tol&&db.abs()<=tol{
    let pa=p2(a,axis);let u=sub2(p2(b,axis),pa);let mut cuts=vec![0.,1.];
    for &(c,d) in &boundary{
     let c=p2(c,axis);let v=sub2(p2(d,axis),c);let det=cross2(u,v);
     if det.abs()>1e-16{let w=sub2(c,pa);let t=cross2(w,v)/det;let s=cross2(w,u)/det;if (0.0..=1.0).contains(&t)&&(0.0..=1.0).contains(&s){cuts.push(t)}}
    }
    cuts.sort_by(f64::total_cmp);
    for pair in cuts.windows(2){let t=(pair[0]+pair[1])*0.5;if inside(add(a,mul(sub(b,a),t)),&boundary,axis,tol){return Err("B-rep edge overlaps nonincident planar face".into())}}
   }else if (da>=-tol&&db<=tol)||(db>=-tol&&da<=tol){
    let t=da/(da-db);
    if (0.0..=1.0).contains(&t)&&inside(add(a,mul(sub(b,a),t)),&boundary,axis,tol){return Err("B-rep edge crosses planar face".into())}
   }
  }
 }
 Ok(())
}
#[cfg(test)] mod tests{
 use super::*;
 #[test] fn interior_and_contact_guards(){
  assert!(segment_distance2([0.,0.,0.],[1.,1.,0.],[1.,0.,0.],[0.,1.,0.])<1e-12);
  assert!((segment_distance2([0.,0.,0.],[1.,0.,0.],[0.,2.,0.],[1.,2.,0.])-4.).abs()<1e-12);
  let boundary=vec![([0.,0.,0.],[2.,0.,0.]),([2.,0.,0.],[2.,2.,0.]),([2.,2.,0.],[0.,2.,0.]),([0.,2.,0.],[0.,0.,0.])];
  assert!(inside([1.,1.,0.],&boundary,2,1e-5));assert!(!inside([2.,1.,0.],&boundary,2,1e-5));
  assert!(!inside([3.,1.,0.],&boundary,2,1e-5));
 }
}
