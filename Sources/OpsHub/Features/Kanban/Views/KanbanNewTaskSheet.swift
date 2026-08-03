import AppKit
import SwiftUI

struct KanbanDraftFormState: Equatable {
    var title = ""
    var objective = ""
    var acceptanceCriteriaText = ""
    var workspacePath = ""
    var validatedWorkspacePath: String?
    var priority: KanbanPriority = .normal

    var acceptanceCriteria: [String] {
        acceptanceCriteriaText.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !acceptanceCriteria.isEmpty
            && validatedWorkspacePath == workspacePath
    }
}

enum KanbanNewTaskFocusTarget: Equatable {
    case newTaskButton
}

enum KanbanNewTaskFocusRouter {
    static func target(
        previousIsPresenting: Bool,
        isPresenting: Bool
    ) -> KanbanNewTaskFocusTarget? {
        previousIsPresenting && !isPresenting ? .newTaskButton : nil
    }
}

struct KanbanNewTaskSheet: View {
    @ObservedObject var model: KanbanViewModel
    let onClose: () -> Void

    @State private var state = KanbanDraftFormState()
    @State private var isValidating = false
    @State private var isSubmitting = false
    @State private var workspaceValidationMessage: String?
    @AccessibilityFocusState private var isHeadingFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("New Task")
                        .font(.system(.title2, design: .monospaced).bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isHeadingFocused)
                    Text("Creates a workflow in Triage. Starting it is a separate action.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close new task")
            }

            Form {
                TextField("Title", text: $state.title)
                TextField("Objective", text: $state.objective, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Acceptance Criteria", text: $state.acceptanceCriteriaText, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityHint("Enter one acceptance criterion per line")
                workspaceField
                Picker("Priority", selection: $state.priority) {
                    ForEach(KanbanPriority.allCases, id: \.self) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await createTask() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Create Task")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canSubmit || isSubmitting)
                .accessibilityHint("Creates a new workflow in Triage")
            }
        }
        .padding(24)
        .frame(minWidth: 540)
        .onChange(of: state.workspacePath) { _, _ in
            if state.validatedWorkspacePath != state.workspacePath {
                state.validatedWorkspacePath = nil
            }
            workspaceValidationMessage = nil
        }
        .onAppear { isHeadingFocused = true }
        .onExitCommand(perform: onClose)
    }

    private var workspaceField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Workspace Path", text: $state.workspacePath)
                Button("Browse") { browse() }
                    .disabled(isValidating || isSubmitting)
                Button {
                    Task { await validateWorkspace() }
                } label: {
                    if isValidating {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Validate")
                    }
                }
                .disabled(state.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating || isSubmitting)
                .accessibilityLabel("Validate workspace path")
            }
            if let workspaceValidationMessage {
                Label(workspaceValidationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Workspace validation error: \(workspaceValidationMessage)")
            }
        }
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Workspace"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.workspacePath = url.path
        Task { await validateWorkspace() }
    }

    private func validateWorkspace() async {
        let pathBeingValidated = state.workspacePath
        isValidating = true
        defer { isValidating = false }
        do {
            let canonicalPath = try await model.validateDraftWorkspacePath(pathBeingValidated)
            guard state.workspacePath == pathBeingValidated else { return }
            state.workspacePath = canonicalPath
            state.validatedWorkspacePath = canonicalPath
            workspaceValidationMessage = nil
        } catch {
            guard state.workspacePath == pathBeingValidated else { return }
            workspaceValidationMessage = error.localizedDescription
            return
        }
    }

    private func createTask() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let input = KanbanDraftInput(
            title: state.title,
            objective: state.objective,
            acceptanceCriteria: state.acceptanceCriteria,
            workspacePath: state.workspacePath,
            priority: state.priority
        )
        if await model.createDraft(input) {
            onClose()
        }
    }
}
