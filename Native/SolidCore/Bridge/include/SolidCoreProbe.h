#ifndef SOLIDCORE_PROBE_H
#define SOLIDCORE_PROBE_H
#include <stdint.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Opaque, non-reused registry IDs. 0 is invalid; stale/double releases return errors.
   All output pointers must reference writable, aligned storage of the declared capacity.
   No borrowed Rust pointer crosses this ABI. All calls are synchronous; call off the UI thread. */
typedef uint64_t SCHandle;
typedef struct { float x,y,z,nx,ny,nz; } SCVertex;
typedef struct {
    uint64_t vertex_count, triangle_count, face_count, buffer_bytes, tessellation_ns;
    uint64_t body_handle, topology_count;
} SCMeshInfo;
typedef struct { uint64_t live_bodies, live_meshes, mesh_bytes; } SCRegistryStats;
/* Record indices, scoped to body+revision. kind: 0 vertex, 1 edge, 2 face.
   Coordinates: mm Z-up. Only editable planar faces accept signed offsets. */
typedef struct { uint32_t id, kind, editable, reserved; double x,y,z,nx,ny,nz; } SCTopology;
int32_t sc_offset_face(SCHandle source,uint32_t face,double distance_mm,SCHandle *result,uint64_t *elapsed_ns);
int32_t sc_body_validate(SCHandle body);
int32_t sc_mesh_topology_copy(SCHandle mesh,SCTopology *elements,size_t capacity);
typedef struct { double x,y,z; } SCPoint;
typedef struct { uint32_t a,b; } SCEdge;
typedef struct { uint64_t vertex_count,edge_count,face_count,index_count; } SCPolygonInfo;
int32_t sc_body_from_polygons(const SCPoint *points,size_t vertex_count,const uint32_t *offsets,size_t face_count,const uint32_t *indices,size_t index_count,SCHandle *body,uint64_t *elapsed_ns,uint64_t *split_faces);
int32_t sc_mesh_polygon_info(SCHandle mesh,SCPolygonInfo *info);
int32_t sc_mesh_polygon_copy(SCHandle mesh,SCPoint *points,size_t vertex_capacity,SCEdge *edges,size_t edge_capacity,uint32_t *offsets,size_t offset_capacity,uint32_t *indices,size_t index_capacity);
int32_t sc_box(double x,double y,double z,double sx,double sy,double sz,SCHandle *body,uint64_t *elapsed_ns);
int32_t sc_difference(SCHandle target,SCHandle tool,SCHandle *body,uint64_t *elapsed_ns);
int32_t sc_body_release(SCHandle body);
int32_t sc_body_volume(SCHandle body,double *volume_mm3);
int32_t sc_tessellate(SCHandle body,double chord_mm,SCHandle *mesh);
int32_t sc_mesh_info(SCHandle mesh,SCMeshInfo *info);
int32_t sc_mesh_copy(SCHandle mesh,SCVertex *vertices,size_t vertex_capacity,
                     uint32_t *indices,size_t index_capacity,uint32_t *face_ids,size_t face_capacity);
int32_t sc_mesh_release(SCHandle mesh);
int32_t sc_registry_stats(SCRegistryStats *stats);
/* Last error on the calling OS thread. Copy immediately after a failed call on the same thread.
   Returns required bytes including NUL. Copies at most capacity bytes, always terminating. */
size_t sc_error_copy(char *buffer,size_t capacity);
#ifdef __cplusplus
}
#endif
#endif
