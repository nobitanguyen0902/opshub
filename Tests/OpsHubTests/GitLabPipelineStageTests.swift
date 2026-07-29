import XCTest
@testable import OpsHub

final class GitLabPipelineStageTests: XCTestCase {
    func testDetailsGroupJobsIntoStableStageOrder() {
        let details = GitLabPipelineDetails(
            pipeline: GitLabPipelineKey(projectID: 7, pipelineID: 42),
            jobs: [
                job(id: 4, name: "deploy", stage: "deploy", status: .manual),
                job(id: 3, name: "integration", stage: "test", status: .pending),
                job(id: 2, name: "unit", stage: "test", status: .success),
                job(id: 1, name: "compile", stage: "build", status: .success)
            ]
        )

        XCTAssertEqual(details.stages.map(\.name), ["build", "test", "deploy"])
        XCTAssertEqual(details.stages[1].jobs.map(\.name), ["unit", "integration"])
    }

    func testManualStageOffersBuildForPlayableJobsOnly() {
        let stage = GitLabPipelineStage(
            name: "deploy",
            jobs: [
                job(id: 1, name: "deploy-prod", stage: "deploy", status: .manual),
                job(id: 2, name: "archived", stage: "deploy", status: .manual, isArchived: true)
            ]
        )

        XCTAssertEqual(stage.status, .manual)
        XCTAssertEqual(stage.availableAction, .build)
        XCTAssertEqual(stage.actionableJobs(for: .build).map(\.id), [1])
    }

    func testFailedAndCanceledStagesOfferRetry() {
        let failed = GitLabPipelineStage(
            name: "test",
            jobs: [job(id: 1, name: "unit", stage: "test", status: .failed)]
        )
        let canceled = GitLabPipelineStage(
            name: "build",
            jobs: [job(id: 2, name: "compile", stage: "build", status: .canceled)]
        )

        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.availableAction, .retry)
        XCTAssertEqual(canceled.status, .canceled)
        XCTAssertEqual(canceled.availableAction, .retry)
    }

    func testActiveStageOffersCancelAndSuccessStageHasNoMutation() {
        let running = GitLabPipelineStage(
            name: "test",
            jobs: [job(id: 1, name: "unit", stage: "test", status: .running)]
        )
        let success = GitLabPipelineStage(
            name: "build",
            jobs: [job(id: 2, name: "compile", stage: "build", status: .success)]
        )

        XCTAssertEqual(running.status, .running)
        XCTAssertEqual(running.availableAction, .cancel)
        XCTAssertEqual(success.status, .success)
        XCTAssertNil(success.availableAction)
    }

    private func job(
        id: Int,
        name: String,
        stage: String,
        status: GitLabJobStatus,
        isArchived: Bool = false
    ) -> GitLabJob {
        GitLabJob(
            id: id,
            name: name,
            stage: stage,
            status: status,
            allowFailure: false,
            isArchived: isArchived,
            failureReason: nil,
            duration: nil,
            webURL: nil
        )
    }
}
