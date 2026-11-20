import BroomCore
import SwiftUI

/// The chats a search found, or a line saying why there are none. Used by the popover and by the search window.
struct SearchResultsList: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    let model: SearchModel
    /// Called after a result is opened.
    var didOpen: () -> Void = {}

    var body: some View {
        if model.results.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
                .padding(.horizontal, 16)
        } else {
            LazyVStack(spacing: 4) {
                ForEach(model.results) { result in
                    Button {
                        model.selectedID = result.id
                        open(result.chat)
                    } label: {
                        SearchResultRow(result: result, isSelected: result.id == model.selectedID)
                    }
                    .buttonStyle(.plain)
                    .id(result.id)
                }
            }
            .padding(8)
        }
    }

    private var emptyMessage: String {
        if !model.query.trimmingCharacters(in: .whitespaces).isEmpty { return "No chats match." }
        if model.indexedCount == 0 { return model.isIndexing ? "Reading your chats for the first time…" : "No chats indexed yet." }
        return "Search by words or by what a chat was about."
    }

    private func open(_ chat: IndexedChat) {
        actions?.open(chat)
        didOpen()
    }
}
