import Foundation

/// Caller-owned identity for ONE immutable operation version. Not a recovery ACK.
struct OfflineOperationKey: Hashable, Codable {
    let rawValue: String
}

struct OfflineMutationReceipt: Codable, Equatable {
    let mutationID: UUID
    let operationKey: OfflineOperationKey
    let createdAt: Date
}

struct OfflineMutationRecord: Codable, Equatable {
    enum State: String, Codable { case attempting, delivered, discarded, uncertain }
    let operationKey: OfflineOperationKey
    // Nil only when corrupt storage prevents identifying the original mutation.
    let receipt: OfflineMutationReceipt?
    var state: State
    let createdAt: Date
    var updatedAt: Date
    var statusCode: Int?
    var reason: String?
}

enum OfflineMutationStatus: Equatable {
    case notFound
    case pending(OfflineMutationReceipt)
    case delivered(OfflineMutationRecord)
    case discarded(OfflineMutationRecord)
    case uncertain(OfflineMutationRecord)
}

enum OfflineCorrelationError: Error {
    case invalidKey, payloadConflict, corruptStorage, persistenceFailed
    case existing(OfflineMutationStatus)
}

enum CorrelatedOfflinePostOutcome {
    case response(Data)
    case queued(OfflineMutationReceipt)
}

/// One API mutation that needs to be sent to the server.
/// Stored in UserDefaults (JSON) so it survives app restarts and offline periods.
struct PendingMutation: Codable {

    var id:           UUID
    var endpoint:     String
    var method:       String
    var payloadData:  Data
    var createdAt:    Date
    var retryCount:   Int
    var isSynced:     Bool
    var nextRetryAt:  Date?
    var operationKey: OfflineOperationKey? // Missing in legacy JSON is valid.

    init(endpoint: String, method: String = "POST", payload: [String: Any]) {
        self.id          = UUID()
        self.endpoint    = endpoint
        self.method      = method
        self.payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        self.createdAt   = Date()
        self.retryCount  = 0
        self.isSynced    = false
        self.nextRetryAt = nil
    }

    init(endpoint: String, method: String, payloadData: Data, operationKey: OfflineOperationKey) {
        self.init(endpoint: endpoint, method: method, payload: [:])
        self.payloadData = payloadData
        self.operationKey = operationKey
    }

    var receipt: OfflineMutationReceipt? {
        operationKey.map { .init(mutationID: id, operationKey: $0, createdAt: createdAt) }
    }

    var payloadDict: [String: Any]? {
        try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
    }
}
