import SwiftUI

/// The popover's search field. Typing in it replaces the tabs with the chats that match.
///
/// Without a search model, as in previews, it is a field that goes nowhere.
struct PopoverSearchField: View {
    @Environment(SessionActionsModel.self) private var actions: SessionActionsModel?
    @Environment(SearchModel.self) private var search: SearchModel?
    @State private var previewQuery = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search all chats", text: query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(openSelected)
                .onKeyPress(.downArrow) { move(by: 1) }
                .onKeyPress(.upArrow) { move(by: -1) }
                .onKeyPress(.escape) { clear() }
                .onKeyPress(KeyEquivalent("c"), phases: .down) { press in
                    press.modifiers.contains(.command) ? copySelected() : .ignored
                }
            if query.wrappedValue.isEmpty {
                Text("⌥⌘B")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help("Search from any app")
                    .accessibilityLabel("Option Command B searches from any app")
            } else {
                Button("Clear", systemImage: "xmark.circle.fill") { query.wrappedValue = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .modifier(ControlSurface())
        .task(id: search?.query) { await search?.updateResults() }
    }

    private var query: Binding<String> {
        if let search {
            @Bindable var search = search
            return $search.query
        }
        return $previewQuery
    }

    private func move(by offset: Int) -> KeyPress.Result {
        guard let search, !search.results.isEmpty else { return .ignored }
        search.moveSelection(by: offset)
        return .handled
    }

    private func openSelected() {
        guard let chat = search?.selected?.chat else { return }
        actions?.open(chat)
    }

    private func copySelected() -> KeyPress.Result {
        guard let chat = search?.selected?.chat else { return .ignored }
        actions?.copyResumeCommand(chat)
        return .handled
    }

    private func clear() -> KeyPress.Result {
        guard !query.wrappedValue.isEmpty else { return .ignored }
        query.wrappedValue = ""
        return .handled
    }
}
