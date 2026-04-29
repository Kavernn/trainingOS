import Foundation

// MARK: - Pagination
struct PagedResponse<T: Codable>: Codable {
    let items: [T]
    let offset: Int
    let limit: Int
    let total: Int
    let hasMore: Bool
    let nextOffset: Int?
    enum CodingKeys: String, CodingKey {
        case items, offset, limit, total
        case hasMore    = "has_more"
        case nextOffset = "next_offset"
    }
}

struct SafeString: Codable {
    let value: String

    init(_ value: String) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let str = try? container.decode(String.self) {
            self.value = str
        } else if let arr = try? container.decode([String].self) {
            self.value = arr.joined(separator: ", ")
        } else if let num = try? container.decode(Double.self) {
            self.value = String(num)
        } else {
            self.value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
