// Copyright (c) 2026 Design Studio Butterfly Effect
// SPDX-License-Identifier: MIT

import Foundation
import RealityKit

struct EditTargetComponent: Component {
    let selection: Selection
    let objectID: UUID
    let revision: UInt64
}

@MainActor
enum SelectionController {
    static func target(for entity: Entity, mode: EditMode, objectID: UUID, revision: UInt64) -> Selection? {
        guard let component = entity.components[EditTargetComponent.self],
              component.objectID == objectID, component.revision == revision,
              component.selection.mode == mode, entity.isEnabledInHierarchy else { return nil }
        return component.selection
    }
}
