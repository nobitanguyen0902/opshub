import SwiftUI

struct KanbanView: View {
    @StateObject private var model: KanbanViewModel
    init(model: KanbanViewModel = KanbanViewModel()) { _model = StateObject(wrappedValue: model) }
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Text("Kanban").font(.title2.bold()); Spacer(); Button("Refresh") { Task { await model.refresh() } } }
            if let message = model.errorMessage { Text(message).foregroundStyle(.red) }
            ScrollView(.horizontal) {
                HStack(alignment: .top) {
                    ForEach(KanbanStatus.allCases) { status in
                        VStack(alignment: .leading) {
                            Text(status.title).font(.headline)
                            ForEach(model.snapshot?.tasks.filter { $0.status == status } ?? []) { task in
                                Button { Task { await model.select(task) } } label: {
                                    VStack(alignment: .leading) { Text(task.title).lineLimit(2); Text(task.id).font(.caption).foregroundStyle(.secondary) }
                                        .padding(8).frame(width: 220, alignment: .leading).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                            }
                        }.frame(width: 240, alignment: .leading)
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
