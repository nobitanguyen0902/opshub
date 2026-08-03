import SwiftUI

struct KanbanView: View {
    @StateObject private var model: KanbanViewModel
    init(model: KanbanViewModel = KanbanViewModel()) { _model = StateObject(wrappedValue: model) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Kanban").font(.title2.bold())
                    Text("Work in progress").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
                Button("Refresh") { Task { await model.refresh() } }
            }
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            if !model.isLoading, model.snapshot?.tasks.isEmpty == true {
                ContentUnavailableView("No tasks yet", systemImage: "checklist", description: Text("Tasks will appear here when they are added to the board."))
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top) {
                    ForEach(KanbanStatus.allCases) { status in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(status.title).font(.headline)
                                Spacer()
                                Text("\(model.snapshot?.tasks.filter { $0.status == status }.count ?? 0)")
                                    .font(.caption.monospacedDigit().bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)
                            ForEach(model.snapshot?.tasks.filter { $0.status == status } ?? []) { task in
                                Button { Task { await model.select(task) } } label: {
                                    VStack(alignment: .leading) { Text(task.title).lineLimit(2); Text(task.id).font(.caption).foregroundStyle(.secondary) }
                                        .padding(8).frame(width: 220, alignment: .leading).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .frame(width: 264, alignment: .leading)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
                    }
                }.padding()
            }
        }.padding().task {
            await model.refresh()
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(5)); await model.refresh() }
        }.sheet(item: $model.selectedDetail) { detail in
            ScrollView { VStack(alignment: .leading, spacing: 12) { Text(detail.task.title).font(.title); Text(detail.task.body); if let result = detail.task.result { Text(result) }; ForEach(detail.comments) { Text("\($0.author): \($0.body)") }; ForEach(detail.events) { event in Text(event.kind).font(.caption.monospaced()) } }.padding() }
        }
    }
}
