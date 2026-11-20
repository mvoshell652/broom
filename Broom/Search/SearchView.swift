import BroomCore
import SwiftUI

/// The search window: a field, the chats that match, and what the keys do.
struct SearchView: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    @Bindable var model: SearchModel
    /// Closes the window.
    let close: () -> Void
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                BroomGlyph()
                    .stroke(BroomStyle.waitingText, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                TextField("Search all chats", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFieldFocused)
                    .onSubmit(openSelected)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            Divider()
            results
            Divider()
            SearchFooter(resultCount: model.results.count, indexedCount: model.indexedCount, isIndexing: model.isIndexing)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .modifier(SearchSurface())
        .task(id: model.query) { await model.updateResults() }
        .onChange(of: model.presentationCount, initial: true) { isFieldFocused = true }
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onKeyPress(KeyEquivalent("c"), phases: .down) { press in
            press.modifiers.contains(.command) ? copySelected() : .ignored
        }
    }

    static let size = CGSize(width: 680, height: 540)

    @ViewBuilder private var results: some View {
        if model.results.isEmpty {
            SearchResultsList(model: model)
                .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    SearchResultsList(model: model, didOpen: close)
                }
                .onChange(of: model.selectedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        model.moveSelection(by: offset)
        return .handled
    }

    private func openSelected() {
        guard let chat = model.selected?.chat else { return }
        actions?.open(chat)
        close()
    }

    private func copySelected() -> KeyPress.Result {
        guard let chat = model.selected?.chat else { return .ignored }
        actions?.copyResumeCommand(chat)
        return .handled
    }
}
