// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import ARKit
import RealityKit
import QuartzCore

@MainActor final class ScenePlacement {
    private let session = ARKitSession()

    func place(workspace: WorkspaceModel) async {
        guard WorldTrackingProvider.isSupported else {
            workspace.errorMessage = "このデバイスではワールドトラッキングを利用できません。"
            return
        }
        let provider = WorldTrackingProvider()
        do {
            try await session.run([provider])
            for _ in 0..<150 {
                try Task.checkCancellation()
                if provider.state == .running,
                   let anchor = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()), anchor.isTracked {
                    let transform = anchor.originFromAnchorTransform
                    let head = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
                    var forward = SIMD3<Float>(-transform.columns.2.x, 0, -transform.columns.2.z)
                    if simd_length(forward) < 0.001 { forward = [0, 0, -1] }
                    forward = simd_normalize(forward)
                    var placement = Transform()
                    placement.translation = head + forward * 0.9 + SIMD3<Float>(0, -0.35, 0)
                    placement.rotation = simd_quatf(angle: atan2(-forward.x, -forward.z), axis: [0, 1, 0])
                    workspace.placeSessions(at: placement)
                    return
                }
                try await Task.sleep(for: .milliseconds(33))
            }
            workspace.errorMessage = "頭の位置を取得できませんでした。空間を閉じ、周囲を見渡してから開き直してください。"
        } catch is CancellationError { session.stop() }
        catch { workspace.errorMessage = "空間の初期化に失敗しました: \(error.localizedDescription)" }
    }

    func stop() { session.stop() }
}
