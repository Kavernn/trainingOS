import Foundation
import SwiftData

/// One API mutation that needs to be sent to the server.
/// Persisted locally so it survives app restarts and offline periods.
@Model
final class PendingMutation {

    // MARK: - Stored properties

    var id:          UUID
    var endpoint:    String   // e.g. "/api/log"
    var method:      String   // always "POST" for now
    var payloadData: Data     // JSON-encoded body
    var createdAt:   Date
    var retryCount:  Int
    var isSynced:    Bool

    // MARK: - Init

    init(endpoint: String, method: String = "POST", payload: [String: Any]) {
        self.id          = UUID()
        self.endpoint    = endpoint
        self.method      = method
        self.payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        self.createdAt   = Date()
        self.retryCount  = 0
        self.isSynced    = false
    }

    // MARK: - Helpers

    var payloadDict: [String: Any]? {
        try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
    }
}
