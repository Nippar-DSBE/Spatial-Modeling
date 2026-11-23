// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import Observation
import RealityKit
import simd
#if canImport(UIKit)
import UIKit
private typealias ObjectColor = UIColor
#else
import AppKit
private typealias ObjectColor = NSColor
#endif

enum ModelingSelection: String, CaseIterable, Identifiable { case object = "Object", vertex = "Vertex", edge = "Edge", face = "Face"; var id: Self { self } }
struct ObjectPose: Codable, Equatable, Sendable {
    var translation: SIMD3<Float>
    var rotation: SIMD4<Float>
    var scale: Float
    init(_ t: Transform = Transform()) { translation = t.translation; rotation = t.rotation.vector; scale = t.scale.x }
    var transform: Transform { Transform(scale: SIMD3(repeating: scale), rotation: simd_quatf(vector: rotation), translation: translation) }
    var valid: Bool { translation.allFinite && rotation.x.isFinite && rotation.y.isFinite && rotation.z.isFinite && rotation.w.isFinite && scale.isFinite && (0.01...10).contains(scale) && abs(simd_length(rotation) - 1) < 0.001 }
}
/// Transportable display-only command. Does not contain CAD or mesh geometry.
struct ObjectTransformCommand: Codable, Sendable {
    var version: UInt32 = 1
    let commandID: UUID
    let objectID: UUID
    let expectedRevision: UInt64
    let before: ObjectPose
    let after: ObjectPose
}
struct ObjectTarget: Component { let objectID: UUID; let revision: UInt64 }

enum WorkspaceHistoryEntry {
    case shape, transform(ObjectTransformCommand)
    case meshConversion(before: MeshDocument, after: MeshDocument, beforePose: ObjectPose, afterPose: ObjectPose)
    case cadConversion(beforePose: ObjectPose, afterPose: ObjectPose)
}
struct WorkspaceHistory {
    var undo: [WorkspaceHistoryEntry] = []
    var redo: [WorkspaceHistoryEntry] = []
    let limit: Int
    mutating func record(_ entry: WorkspaceHistoryEntry) {
        undo.append(entry); if undo.count > limit { undo.removeFirst() }; redo.removeAll()
    }
}

@MainActor @Observable final class ObjectTransformSession {
    let objectID: UUID
    @ObservationIgnored let root: Entity
    @ObservationIgnored let target = ModelEntity()
    private(set) var revision: UInt64 = 0
    private(set) var pose = ObjectPose()
    private(set) var isEditing = false
    private(set) var source: Source?
    private(set) var initialized = false
    var errorMessage: String?
    @ObservationIgnored var onCommit: ((ObjectTransformCommand) -> Void)?
    @ObservationIgnored private var baseline = ObjectPose()
    @ObservationIgnored private var start: ObjectPose?
    @ObservationIgnored private var lastTranslation = SIMD3<Float>.zero
    @ObservationIgnored private var lastMagnification: Float = 1
    @ObservationIgnored private var lastRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    @ObservationIgnored private var center = SIMD3<Float>.zero
    @ObservationIgnored private var targetBounds: (SIMD3<Float>, SIMD3<Float>)?
    enum Source { case gesture, slider }
    var percent: Double { Double(pose.scale) * 100 }

    init(objectID: UUID, root: Entity) { self.objectID = objectID; self.root = root }
    func place(_ transform: Transform) {
        guard !initialized else { return }
        baseline = ObjectPose(transform); pose = baseline; root.transform = transform; initialized = true
    }
    func syncTarget(points: [SIMD3<Float>], active: Bool) {
        guard let first = points.first else { target.isEnabled = false; return }
        let low = points.reduce(first) { simd_min($0,$1) }, high = points.reduce(first) { simd_max($0,$1) }
        if targetBounds?.0 != low || targetBounds?.1 != high {
            targetBounds = (low,high)
            target.model = ModelComponent(mesh: .generateSphere(radius: 0.007), materials: [UnlitMaterial(color: ObjectColor.white)])
            target.position = [(low.x+high.x)/2, low.y - 0.025, (low.z+high.z)/2]
            let box = ShapeResource.generateBox(size: simd_max(high-low, SIMD3(repeating: 0.002)))
                .offsetBy(translation: (low+high)/2 - target.position)
            target.components.set(CollisionComponent(shapes: [box,.generateSphere(radius: 0.016)]))
            target.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            target.components.set(HoverEffectComponent())
            target.name = "Object transform handle"
        }
        if target.parent !== root { root.addChild(target) }
        target.components.set(ObjectTarget(objectID: objectID, revision: revision))
        target.isEnabled = active
    }
    @discardableResult func begin(center: SIMD3<Float>, source: Source) -> Bool {
        guard !isEditing, initialized, center.allFinite else { return false }
        let current = ObjectPose(root.transform)
        guard current.valid else { return false }
        lastTranslation = .zero; lastMagnification = 1; lastRotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        pose = current; start = current; self.center = center; self.source = source; isEditing = true; errorMessage = nil
        target.model?.materials = [UnlitMaterial(color: ObjectColor.systemOrange)]
        return true
    }
    /// Scene-space deltas measured from the gesture start, applied about the model's local AABB center.
    @discardableResult func preview(translation: SIMD3<Float> = .zero, magnification: Float = 1, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) -> Bool {
        guard let start, isEditing, translation.allFinite, magnification.isFinite, magnification > 0,
              rotation.vector.x.isFinite, rotation.vector.y.isFinite, rotation.vector.z.isFinite, rotation.vector.w.isFinite,
              simd_length(rotation.vector) > 0.0001 else { return false }
        let q = simd_normalize(rotation * simd_quatf(vector: start.rotation))
        let scale = min(10, max(0.01, start.scale * magnification))
        let worldCenter = start.translation + simd_quatf(vector: start.rotation).act(center * start.scale)
        let t = worldCenter + translation - q.act(center * scale)
        let next = ObjectPose(Transform(scale: SIMD3(repeating: scale), rotation: q, translation: t))
        guard next.valid else { return false }
        pose = next; root.transform = next.transform
        return true
    }
    func previewGesture(translation: SIMD3<Float>?, magnification: Float?, rotation: simd_quatf?) {
        let t = translation ?? lastTranslation, m = magnification ?? lastMagnification, r = rotation ?? lastRotation
        if preview(translation: t, magnification: m, rotation: r) {
            lastTranslation = t; lastMagnification = m; lastRotation = r
        }
    }
    @discardableResult func previewPercent(_ percent: Double) -> Bool {
        guard percent.isFinite, (1...1000).contains(percent), let start else { errorMessage = "Enter a finite scale from 1% to 1000%."; return false }
        return preview(magnification: Float(percent / 100) / start.scale)
    }
    func finish() {
        guard let before = start else { return }
        start = nil; isEditing = false; source = nil
        target.model?.materials = [UnlitMaterial(color: ObjectColor.white)]
        guard before != pose else { return }
        let command = ObjectTransformCommand(commandID: UUID(), objectID: objectID, expectedRevision: revision, before: before, after: pose)
        revision += 1; onCommit?(command)
    }
    func cancel() {
        if let start { pose = start; root.transform = start.transform }
        start = nil; isEditing = false; source = nil
        target.model?.materials = [UnlitMaterial(color: ObjectColor.white)]
    }
    @discardableResult func reset() -> Bool {
        guard !isEditing, initialized else { return false }
        let before = ObjectPose(root.transform)
        guard before != baseline else { return true }
        let command = ObjectTransformCommand(commandID: UUID(), objectID: objectID, expectedRevision: revision, before: before, after: baseline)
        return execute(command)
    }
    @discardableResult func execute(_ command: ObjectTransformCommand) -> Bool {
        guard !isEditing, command.version == 1, command.objectID == objectID, command.expectedRevision == revision,
              command.before == ObjectPose(root.transform), command.before.valid, command.after.valid else { return false }
        pose = command.after; root.transform = pose.transform; revision += 1; onCommit?(command)
        return true
    }
    func restore(_ pose: ObjectPose) { guard !isEditing, pose.valid else { return }; self.pose = pose; root.transform = pose.transform; revision += 1 }
}
