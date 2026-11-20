import SwiftUI

/// The bottom of the search window: what the keys do, and how much was searched.
struct SearchFooter: View {
    let resultCount: Int
    let indexedCount: Int
    let isIndexing: Bool

    var body: some View {
        HStack(spacing: 16) {
            hint("↩", "Open")
            ViewThatFits {
                hint("⌘C", "Copy resume command")
                EmptyView()
            }
            Spacer()
            Text(status)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key).fontWeight(.semibold).foregroundStyle(.primary)
            Text(action)
        }
        .accessibilityElement(children: .combine)
    }

    /// "1 chat indexed", "663 chats indexed": the count is inflected, so one chat is not "1 chats".
    private var status: LocalizedStringKey {
        if isIndexing, resultCount == 0 { return "Indexing · ^[\(indexedCount) chat](inflect: true) so far" }
        return resultCount == 0 ? "^[\(indexedCount) chat](inflect: true) indexed" : "\(resultCount) of \(indexedCount)"
    }
}
