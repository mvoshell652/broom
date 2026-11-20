import SwiftUI

/// The Settings section for the chat index: how much is in it, and a way to delete it.
struct SearchIndexSection: View {
    let search: SearchModel
    @State private var isConfirmingDelete = false

    var body: some View {
        Section("Search") {
            LabeledContent("Chats indexed", value: search.indexedCount, format: .number)
            Text("Search works from a copy of what you typed and what Claude replied, kept on this Mac. Tool input and output are not copied. Press ⌥⌘B anywhere to search.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Delete Index…", role: .destructive) { isConfirmingDelete = true }
                .disabled(search.indexedCount == 0)
                .confirmationDialog("Delete the search index?", isPresented: $isConfirmingDelete) {
                    Button("Delete Index", role: .destructive) {
                        Task { await search.deleteIndex() }
                    }
                } message: {
                    Text("Your chats are not touched. Broom reads them again within a minute and rebuilds the index.")
                }
        }
    }
}
