import Foundation

protocol GitLabServicing: Sendable {
    func dashboardStatistics() async throws -> [GitLabStatistic]
    func mergeRequests() async throws -> [GitLabMergeRequest]
    func issues() async throws -> [GitLabIssue]
    func notifications() async throws -> [GitLabNotification]
    func pipelines() async throws -> [GitLabPipeline]
}

struct GitLabMockService: GitLabServicing {
    private let networkDelay: Duration

    init(networkDelay: Duration = .milliseconds(350)) {
        self.networkDelay = networkDelay
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

    private func simulateNetworkDelay() async throws {
        try await Task.sleep(for: networkDelay)
    }
}
