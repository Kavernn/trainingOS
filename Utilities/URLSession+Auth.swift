import Foundation

extension URLSession {
    /// Authenticated session — injects Authorization header on every request.
    /// Use instead of URLSession.shared for all TrainingOS API calls.
    static let authed: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Authorization": "Bearer \(APIConfig.apiKey)"
        ]
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()
}
