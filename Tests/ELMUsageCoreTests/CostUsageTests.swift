import ELMUsageCore
import Foundation
import Testing

@Suite("CostUsage & Formatting")
struct CostUsageTests {
    @Test("Decodes API response and formats as USD ignoring GBP currency typo")
    func decodeAndFormat() throws {
        let json = """
        {
            "usage": 482.34,
            "limit": 500.0,
            "currency": "GBP",
            "asOf": "2026-11-22T00:00:00Z"
        }
        """
        let response = try JSONDecoder().decode(CostUsageResponse.self, from: Data(json.utf8))
        let snapshot = UsageSnapshot(response: response)

        #expect(snapshot.formattedUsage == "$482.34")
        #expect(snapshot.formattedLimit == "$500.00")
        #expect(snapshot.formattedPercentage == "96.5%")
        #expect(snapshot.remainingLine == "Remaining: $17.66")
        #expect(snapshot.thresholdLevel == .critical)
        #expect(!snapshot.isOverLimit)
    }

    @Test("Decodes response even if currency and asOf are omitted")
    func decodeMinimalPayload() throws {
        let json = #"{"usage": 480.0128, "limit": 500.0}"#
        let response = try JSONDecoder().decode(CostUsageResponse.self, from: Data(json.utf8))
        let snapshot = UsageSnapshot(response: response)

        #expect(snapshot.formattedUsage == "$480.01")
        #expect(snapshot.formattedLimit == "$500.00")
        #expect(snapshot.formattedPercentage == "96.0%")
        #expect(snapshot.remainingLine == "Remaining: $19.99")
    }

    @Test("Threshold boundaries match <65%, 65-85%, >=85%")
    func thresholdBoundaries() {
        #expect(ThresholdLevel.forFraction(0.0) == .normal)
        #expect(ThresholdLevel.forFraction(0.6499) == .normal)
        #expect(ThresholdLevel.forFraction(0.65) == .warning)
        #expect(ThresholdLevel.forFraction(0.8499) == .warning)
        #expect(ThresholdLevel.forFraction(0.85) == .critical)
        #expect(ThresholdLevel.forFraction(1.25) == .critical)
    }

    @Test("Handles over-limit usage cleanly")
    func overLimit() {
        let snapshot = UsageSnapshot(usage: 512.50, limit: 500.0)

        #expect(snapshot.isOverLimit)
        #expect(snapshot.clampedFraction == 1.0)
        #expect(snapshot.formattedPercentage == "102.5%")
        #expect(snapshot.remainingLine == "Over limit: $12.50")
        #expect(snapshot.thresholdLevel == .critical)
    }

    @Test("Handles zero limit safely without NaN")
    func zeroLimit() {
        let snapshot = UsageSnapshot(usage: 10.0, limit: 0.0)

        #expect(snapshot.fraction == 0.0)
        #expect(snapshot.clampedFraction == 0.0)
        #expect(snapshot.formattedPercentage == "0.0%")
    }

    @Test("Environment key lookup trims whitespace")
    func envKeyTrimming() {
        let store = KeychainStore(service: "test.service.unused.\(UUID().uuidString)", account: "unused")
        let key = store.readEnvironmentKey(environment: ["ELM_API_KEY": "  sk-test-123 \n"])
        #expect(key == "sk-test-123")

        let empty = store.readEnvironmentKey(environment: ["ELM_API_KEY": "   \n "])
        #expect(empty == nil)
    }

    @Test("Parses static shell dotfile assignments across quote styles")
    func parseShellDotfileAssignments() {
        let zshrc = """
        # export ELM_API_KEY='commented-out'
        export ELM_API_KEY="first-key"
        export ELM_API_KEY='single-quoted-key' # trailing note
        export ELM_API_KEY
        """
        #expect(KeychainStore.parseShellAssignment(in: zshrc, variableName: "ELM_API_KEY") == "single-quoted-key")

        let unquoted = "ELM_API_KEY=plain_value_123 # inline comment\n"
        #expect(KeychainStore.parseShellAssignment(in: unquoted, variableName: "ELM_API_KEY") == "plain_value_123")

        let dynamic = """
        export ELM_API_KEY="$(cat ~/.secret)"
        export ELM_API_KEY=$OTHER_VAR
        """
        #expect(KeychainStore.parseShellAssignment(in: dynamic, variableName: "ELM_API_KEY") == nil)
    }

    @Test("Resolves key from shell dotfiles in home directory when env is empty")
    func resolvesFromDotfileInHomeDir() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("elm-test-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        try "export ELM_API_KEY='from-zprofile'\n".write(
            to: tempHome.appendingPathComponent(".zprofile"),
            atomically: true,
            encoding: .utf8
        )
        try "export ELM_API_KEY='from-zshrc'\nexport ELM_API_KEY\n".write(
            to: tempHome.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )

        let store = KeychainStore(service: "test.service.unused.\(UUID().uuidString)", account: "unused")
        let resolved = store.resolveKey(environment: [:], homeDirectory: tempHome)
        #expect(resolved.value == "from-zshrc")
        #expect(resolved.source == .environment)
    }
}

@Suite("CostsClient", .serialized)
struct CostsClientTests {
    final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test("Sends Bearer auth header and parses valid response")
    func successfulFetch() async throws {
        let endpoint = URL(string: "https://elm.edina.ac.uk/api/v1/costs")!
        let payload = Data(#"{"usage": 125.5, "limit": 500.0, "currency": "GBP", "asOf": "2026-11-22T00:00:00Z"}"#.utf8)

        StubURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
            let response = HTTPURLResponse(url: endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, payload)
        }

        let client = CostsClient(endpoint: endpoint, session: makeSession())
        let snapshot = try await client.fetchUsage(apiKey: " secret-key \n")

        #expect(snapshot.usage == 125.5)
        #expect(snapshot.limit == 500.0)
        #expect(snapshot.thresholdLevel == .normal)
    }

    @Test("Maps HTTP 401 to CostsError.unauthorized")
    func unauthorizedFetch() async {
        let endpoint = URL(string: "https://elm.edina.ac.uk/api/v1/costs")!
        StubURLProtocol.handler = { _ in
            let response = HTTPURLResponse(url: endpoint, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let client = CostsClient(endpoint: endpoint, session: makeSession())
        await #expect(throws: CostsError.unauthorized) {
            _ = try await client.fetchUsage(apiKey: "bad-key")
        }
    }

    @Test("Rejects blank API key before making a network call")
    func missingKeyThrows() async {
        let client = CostsClient(session: makeSession())
        await #expect(throws: CostsError.missingAPIKey) {
            _ = try await client.fetchUsage(apiKey: "   ")
        }
    }
}
