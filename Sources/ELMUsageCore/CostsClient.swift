import Foundation

public enum CostsError: LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case unauthorized
    case httpStatus(Int)
    case invalidResponse
    case network(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API key not configured."
        case .unauthorized:
            return "API key rejected (unauthorized)."
        case .httpStatus(let code):
            return "Server returned HTTP \(code)."
        case .invalidResponse:
            return "Unexpected server response."
        case .network(let message):
            return message
        case .decoding(let message):
            return "Failed to parse usage data: \(message)"
        }
    }
}

public protocol CostsFetching: Sendable {
    func fetchUsage(apiKey: String) async throws -> UsageSnapshot
}

public struct CostsClient: CostsFetching {
    public static let defaultEndpoint = URL(string: "https://elm.edina.ac.uk/api/v1/costs")!

    private let endpoint: URL
    private let session: URLSession
    private let timeout: TimeInterval

    public init(
        endpoint: URL = CostsClient.defaultEndpoint,
        session: URLSession = .shared,
        timeout: TimeInterval = 30
    ) {
        self.endpoint = endpoint
        self.session = session
        self.timeout = timeout
    }

    public func fetchUsage(apiKey: String) async throws -> UsageSnapshot {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw CostsError.missingAPIKey
        }

        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw CostsError.network(error.localizedDescription)
        } catch {
            throw CostsError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CostsError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ... 299:
            break
        case 401, 403:
            throw CostsError.unauthorized
        default:
            throw CostsError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(CostUsageResponse.self, from: data)
            return UsageSnapshot(response: decoded, fetchedAt: Date())
        } catch {
            throw CostsError.decoding(error.localizedDescription)
        }
    }
}
