import Testing

extension Tag {
    /// Tests that start processes, open sockets or watch the file system, so a fast loop can leave them out.
    @Tag static var integration: Self
}
