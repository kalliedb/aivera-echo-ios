import SwiftUI

/// Index of all user-owned lists (iOS port of Android's ListsScreen).
/// Each row navigates to ListDetailView. The "+" toolbar button presents
/// a new-list sheet (name + type picker).
struct ListsView: View {

    @EnvironmentObject private var listRepo: ListRepository
    @Environment(\.dismiss) private var dismiss
    @State private var showNewList = false

    var body: some View {
        Group {
            if listRepo.lists.isEmpty {
                ContentUnavailableView(
                    "No lists yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Tap + to create your first list — shopping, packing, ideas, or anything else.")
                )
            } else {
                List {
                    ForEach(listRepo.lists) { list in
                        NavigationLink(value: list) {
                            row(for: list)
                        }
                    }
                    .onDelete(perform: deleteLists)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: TaskList.self) { list in
            ListDetailView(list: list)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { showNewList = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New list")
            }
        }
        .sheet(isPresented: $showNewList) {
            NewListSheet { name, type in
                Task { try? await listRepo.addList(name: name, type: type) }
            }
        }
    }

    @ViewBuilder
    private func row(for list: TaskList) -> some View {
        HStack(spacing: 12) {
            Image(systemName: list.type.symbol)
                .foregroundStyle(Color.echoAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name).font(.body.weight(.medium))
                Text(list.type.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func deleteLists(at offsets: IndexSet) {
        let toDelete = offsets.map { listRepo.lists[$0] }
        for list in toDelete {
            Task { try? await listRepo.deleteList(list) }
        }
    }
}

/// "+ New list" sheet — name field + type picker. Tapping Create commits.
private struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var type: ListType = .custom
    let onCreate: (String, ListType) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("List name") {
                    TextField("e.g. Groceries", text: $name)
                        .submitLabel(.done)
                }
                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(ListType.allCases, id: \.self) { t in
                            Label(t.label, systemImage: t.symbol).tag(t)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("New list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines), type)
                        dismiss()
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
