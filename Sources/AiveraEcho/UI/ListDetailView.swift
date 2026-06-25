import GRDB
import SwiftUI

/// Items in a single list. Header carries the list name + type. Bottom has
/// an inline "Add item" text field (Android parity FR-LIST-013). Items can
/// be checked off, deleted via swipe.
///
/// v1 is text-only; voice-append via the mic uses the same SpeechRecognizer
/// pipeline as the home reminder flow but routes the transcript to
/// `addItem` instead of opening ReviewSheet. Wired in a follow-up — the
/// data + UI scaffolding is in place to make it a one-property change.
struct ListDetailView: View {

    let list: TaskList
    @EnvironmentObject private var listRepo: ListRepository
    @State private var items: [TaskListItem] = []
    @State private var newItemText: String = ""
    @State private var observation: AnyDatabaseCancellable?
    @FocusState private var newItemFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                ContentUnavailableView(
                    "No items yet",
                    systemImage: list.type.symbol,
                    description: Text("Type below and tap + to add your first item.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        itemRow(item)
                    }
                    .onDelete(perform: deleteItems)
                }
                .listStyle(.plain)
            }

            Divider()
            addItemBar
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Hand observation lifecycle to ListRepository — it has the
            // concrete database reference that GRDB's generic start(in:)
            // can open. Crossing the existential through an external
            // holder defeats Swift's existential opening.
            observation?.cancel()
            let cancellable = listRepo.observeItems(for: list.id) { fresh in
                Task { @MainActor in items = fresh }
            }
            observation = cancellable
        }
        .onDisappear {
            observation?.cancel()
            observation = nil
        }
    }

    @ViewBuilder
    private func itemRow(_ item: TaskListItem) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { try? await listRepo.setChecked(item, checked: !item.checked) }
            } label: {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.checked ? Color.echoAccent : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(item.text)
                .strikethrough(item.checked)
                .foregroundStyle(item.checked ? Color.secondary : Color.primary)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var addItemBar: some View {
        HStack(spacing: 8) {
            TextField("Add an item", text: $newItemText)
                .focused($newItemFocused)
                .submitLabel(.done)
                .onSubmit(addCurrentItem)
                .textFieldStyle(.roundedBorder)

            Button(action: addCurrentItem) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        canSubmit ? Color.echoAccent : Color.gray.opacity(0.4)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel("Add item")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background)
    }

    private var canSubmit: Bool {
        !newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addCurrentItem() {
        guard canSubmit else { return }
        let text = newItemText
        newItemText = ""
        newItemFocused = true
        Task { try? await listRepo.addItem(to: list, text: text) }
    }

    private func deleteItems(at offsets: IndexSet) {
        let toDelete = offsets.map { items[$0] }
        for item in toDelete {
            Task { try? await listRepo.deleteItem(item) }
        }
    }
}

