import Foundation
import SwiftData

/// Stub model — full field list added in Phase 2 (The Cabinet).
/// See the Data Model doc for the authoritative field list.
@Model
public final class CabinetItem {
    public var id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}
