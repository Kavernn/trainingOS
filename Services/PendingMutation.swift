import Foundation

/// One API mutation that needs to be sent to the server.
/// Stored in UserDefaults (JSON) so it survives app restarts and offline periods.
struct PendingMutation: Codable {

    var id:          UUID
    var endpoint:    String
    var method:      String
    var payloadData: Data
    var createdAt:   Date
    var retryCount:  Int
    var isSynced:    Bool

    init(endpoint: String, method: String = "POST", payload: [String: Any]) {
        self.id          = UUID()
        self.endpoint    = endpoint
        self.method      = method
        self.payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        self.createdAt   = Date()
        self.retryCount  = 0
        self.isSynced    = false
    }

    var payloadDict: [String: Any]? {
        try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
    }
}
