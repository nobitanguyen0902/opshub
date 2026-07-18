### Task 6: Static Dev Room components và detail interaction

**Files:**
- Create: Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift
- Create: Sources/OpsHub/Features/DevRoom/Components/DevRoomHeader.swift
- Create: Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift
- Create: Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift
- Create: Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailPanel.swift
- Modify: Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift

**Interfaces:**
- Consumes: DevRoomData, DevRoomEmployeeSummary, selectedStage, selectedEmployee, ViewModel actions.
- Produces: Static room layout, filter buttons, employee selection, detail panel và openURL.

- [ ] **Step 1: Thêm design tokens và stage colors**

Tạo DevRoomDesignTokens.swift:

~~~swift
import SwiftUI

enum DevRoomDesignTokens {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let cardSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 12

    static func color(for stage: DevRoomWorkflowStage) -> Color {
        switch stage {
        case .todo: .gray
        case .doing: .blue
        case .toTest: .orange
        case .test: .purple
        case .passed: .green
        }
    }
}
~~~

- [ ] **Step 2: Implement header và workflow summary**

DevRoomHeader.swift:

~~~swift
import SwiftUI

struct DevRoomHeader: View {
    let lastUpdated: Date?
    let isRefreshing: Bool
    let isStale: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dev Room").font(.largeTitle.bold())
                Text("\(GitLabWorkflowProject.path) • Open issues có assignee")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isStale {
                Label("Dữ liệu có thể đã cũ", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let lastUpdated {
                Label(lastUpdated.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                    .foregroundStyle(.secondary)
            }
            Button(action: onRefresh) {
                Label(isRefreshing ? "Đang cập nhật" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
        }
    }
}
~~~

DevRoomWorkflowSummary.swift:

~~~swift
import SwiftUI

struct DevRoomWorkflowSummary: View {
    let data: DevRoomData
    let selectedStage: DevRoomWorkflowStage?
    let onSelect: (DevRoomWorkflowStage) -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
            spacing: 12
        ) {
            ForEach(DevRoomWorkflowStage.allCases) { stage in
                Button { onSelect(stage) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(stage.title, systemImage: "circle.fill")
                            .foregroundStyle(DevRoomDesignTokens.color(for: stage))
                        Text("\(data.count(for: stage))")
                            .font(.title.bold())
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding()
                    .background(
                        selectedStage == stage
                            ? DevRoomDesignTokens.color(for: stage).opacity(0.12)
                            : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                            .stroke(
                                selectedStage == stage
                                    ? DevRoomDesignTokens.color(for: stage)
                                    : Color(nsColor: .separatorColor)
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(stage.title), \(data.count(for: stage)) task")
            }
        }
    }
}
~~~

- [ ] **Step 3: Implement employee desk không animation**

Tạo DevRoomEmployeeDesk.swift:

~~~swift
import SwiftUI

struct DevRoomEmployeeDesk: View {
    let summary: DevRoomEmployeeSummary
    let selectedStage: DevRoomWorkflowStage?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                employeeCard
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(height: 100)
                    .overlay {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(summary.employee.name), \(summary.total) task")
    }

    private var employeeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.employee.name).font(.headline)
                    Text("\(summary.total) task")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(summary.previewIssues(for: selectedStage)) { issue in
                Text("• #\(issue.iid) \(issue.title)")
                    .font(.caption)
                    .lineLimit(1)
            }

            HStack(spacing: 0) {
                ForEach(DevRoomWorkflowStage.allCases) { stage in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DevRoomDesignTokens.color(for: stage))
                            .frame(width: 7, height: 7)
                        Text("\(summary.count(for: stage))")
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                .stroke(Color(nsColor: .separatorColor))
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = summary.employee.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
        }
    }
}
~~~

- [ ] **Step 4: Implement detail panel và main static layout**

Tạo DevRoomEmployeeDetailPanel.swift:

~~~swift
import SwiftUI

struct DevRoomEmployeeDetailPanel: View {
    @Environment(\.openURL) private var openURL

    let summary: DevRoomEmployeeSummary
    let preferredStage: DevRoomWorkflowStage?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.employee.name).font(.title2.bold())
                    Text("\(summary.total) task").foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng chi tiết")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(orderedStages) { stage in
                        let issues = summary.issues.filter { $0.stage == stage }
                        if issues.isEmpty == false {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(stage.title, systemImage: "circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(DevRoomDesignTokens.color(for: stage))

                                ForEach(issues) { issue in
                                    issueButton(issue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private var orderedStages: [DevRoomWorkflowStage] {
        guard let preferredStage else { return DevRoomWorkflowStage.allCases }
        return [preferredStage] + DevRoomWorkflowStage.allCases.filter { $0 != preferredStage }
    }

    private func issueButton(_ issue: DevRoomIssue) -> some View {
        Button {
            if let webURL = issue.webURL {
                openURL(webURL)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(issue.iid) \(issue.title)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let updatedAt = issue.updatedAt {
                    Text(updatedAt.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .disabled(issue.webURL == nil)
    }
}
~~~

Thay DevRoomView body bằng:

~~~swift
import SwiftUI

struct DevRoomView: View {
    @ObservedObject var viewModel: DevRoomViewModel

    var body: some View {
        VStack(spacing: 0) {
            DevRoomHeader(
                lastUpdated: viewModel.lastUpdated,
                isRefreshing: viewModel.loadState == .initialLoading || viewModel.loadState == .refreshing,
                isStale: {
                    if case .stale = viewModel.loadState { return true }
                    return false
                }(),
                onRefresh: { Task { await viewModel.refresh() } }
            )
            .padding(DevRoomDesignTokens.pagePadding)

            content
        }
        .navigationTitle("Dev Room")
        .task { await viewModel.loadIfNeeded() }
        .task { await viewModel.autoRefresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .initialLoading:
            ProgressView("Đang tải Dev Room…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Không thể tải Dev Room", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Thử lại") { Task { await viewModel.retry() } }
            }
        default:
            roomContent
        }
    }

    private var roomContent: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DevRoomDesignTokens.sectionSpacing) {
                    DevRoomWorkflowSummary(
                        data: viewModel.data,
                        selectedStage: viewModel.selectedStage,
                        onSelect: viewModel.toggleStage
                    )

                    if viewModel.displayedEmployees.isEmpty {
                        ContentUnavailableView(
                            "Không có task đang mở trong Dev Room",
                            systemImage: "person.3"
                        )
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 260), spacing: 20)],
                            spacing: 24
                        ) {
                            ForEach(viewModel.displayedEmployees) { employee in
                                DevRoomEmployeeDesk(
                                    summary: employee,
                                    selectedStage: viewModel.selectedStage,
                                    onSelect: { viewModel.selectEmployee(employee.id) }
                                )
                            }
                        }
                    }
                }
                .padding(DevRoomDesignTokens.pagePadding)
            }

            if let employee = viewModel.selectedEmployee {
                Divider()
                DevRoomEmployeeDetailPanel(
                    summary: employee,
                    preferredStage: viewModel.selectedStage,
                    onClose: { viewModel.selectEmployee(nil) }
                )
                .frame(width: 340)
            }
        }
    }
}
~~~

- [ ] **Step 5: Build static UI**

Run:

~~~bash
swift build
swift build -c release
~~~

Expected: cả debug/release builds succeed; không có strict-concurrency hoặc ViewBuilder error.

- [ ] **Step 6: Manual static UI verify**

Run:

~~~bash
swift run OpsHub
~~~

Expected:
- menu cũ còn nguyên và Dev Room nằm sau Dashboard;
- header không cuộn;
- năm stage cards đúng order;
- filter không làm mất full counts;
- mỗi employee một card;
- detail panel mở/đóng và issue link mở browser;
- empty/error/loading states không crash.

- [ ] **Step 7: Commit static UI**

~~~bash
git add Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomHeader.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailPanel.swift Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift
git commit -m "feat(dev-room): add employee room interface"
~~~

---

