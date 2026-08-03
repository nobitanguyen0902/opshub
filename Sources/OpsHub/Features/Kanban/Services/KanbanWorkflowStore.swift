import Foundation

protocol KanbanWorkflowStoring: Sendable {
    func load() async throws -> [KanbanWorkflow]
    func save(_ workflows: [KanbanWorkflow]) async throws
}

enum KanbanWorkflowStoreError: LocalizedError, Equatable {
    case corruptData
    case unsupportedSchema(Int)
    case fileOperation(String)

    var errorDescription: String? {
        switch self {
        case .corruptData:
            "Kanban workflow data is corrupt."
        case .unsupportedSchema(let version):
            "Kanban workflow schema version \(version) is unsupported."
        case .fileOperation(let message):
            "Unable to access Kanban workflow storage: \(message)"
        }
    }
}

actor FileKanbanWorkflowStore: KanbanWorkflowStoring {
    private struct WorkflowSchemaVersion: Decodable {
        let schemaVersion: Int
    }

    private let url: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL = FileKanbanWorkflowStore.defaultURL(), fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    static func defaultURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpsHub/Kanban/workflows.json")
    }

    func load() throws -> [KanbanWorkflow] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw KanbanWorkflowStoreError.fileOperation(error.localizedDescription)
        }

        let schemaVersions: [WorkflowSchemaVersion]
        do {
            schemaVersions = try decoder.decode([WorkflowSchemaVersion].self, from: data)
        } catch {
            throw KanbanWorkflowStoreError.corruptData
        }

        for workflow in schemaVersions where workflow.schemaVersion != KanbanWorkflow.currentSchemaVersion {
            throw KanbanWorkflowStoreError.unsupportedSchema(workflow.schemaVersion)
        }

        do {
            return try decoder.decode([KanbanWorkflow].self, from: data)
        } catch {
            throw KanbanWorkflowStoreError.corruptData
        }
    }

    func save(_ workflows: [KanbanWorkflow]) throws {
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(workflows)
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: url.path
            )
        } catch {
            throw KanbanWorkflowStoreError.fileOperation(error.localizedDescription)
        }
    }
}
