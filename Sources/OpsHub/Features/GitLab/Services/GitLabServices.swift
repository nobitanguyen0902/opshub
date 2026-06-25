import Foundation

protocol GitLabServicing: Sendable {
    func dashboardStatistics() async throws -> [GitLabStatistic]
    func mergeRequests() async throws -> [GitLabMergeRequest]
    func issues() async throws -> [GitLabIssue]
    func notifications() async throws -> [GitLabNotification]
    func pipelines() async throws -> [GitLabPipeline]
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult
}

struct GitLabMockService: GitLabServicing {
    private let networkDelay: Duration
    private let connectionResultProvider: @Sendable () -> GitLabConnectionTestResult

    init(
        networkDelay: Duration = .milliseconds(350),
        connectionResultProvider: @escaping @Sendable () -> GitLabConnectionTestResult = {
            GitLabConnectionTestResult.allCases.randomElement() ?? .connected
        }
    ) {
        self.networkDelay = networkDelay
        self.connectionResultProvider = connectionResultProvider
    }

    func dashboardStatistics() async throws -> [GitLabStatistic] {
        try await simulateNetworkDelay()
        return GitLabMocks.statistics
    }

    func mergeRequests() async throws -> [GitLabMergeRequest] {
        try await simulateNetworkDelay()
        return GitLabMocks.mergeRequests
    }

    func issues() async throws -> [GitLabIssue] {
        try await simulateNetworkDelay()
        return GitLabMocks.issues
    }

    func notifications() async throws -> [GitLabNotification] {
        try await simulateNetworkDelay()
        return GitLabMocks.notifications
    }

    func pipelines() async throws -> [GitLabPipeline] {
        try await simulateNetworkDelay()
        return GitLabMocks.pipelines
    }

    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult {
        try await simulateNetworkDelay()
        return connectionResultProvider()
    }

    private func simulateNetworkDelay() async throws {
        try await Task.sleep(for: networkDelay)
    }
}
