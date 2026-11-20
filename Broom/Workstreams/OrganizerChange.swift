/// What a recorded change did, with what is needed to put things back.
public enum OrganizerChange: Codable, Equatable, Sendable {
    /// Chats were merged. `previousGroups` holds every affected chat and the merge group it was in before, if any.
    case merged(previousGroups: [String: String?])
    /// Pairs of chats were marked as not duplicates.
    case markedDistinct(chatIDs: [String])
    /// A chat was filed by hand. `previousWorkstreamID` is where it had been filed by hand before, if anywhere.
    case filed(chatID: String, previousWorkstreamID: Int64?)
    /// A workstream was made for a folder.
    case createdWorkstream(id: Int64)
    /// Chats were archived.
    case archived(chatIDs: [String])
    /// An open loop was marked done. `previouslyClosedAt` is when it had been marked done before, if ever.
    case closedLoop(chatID: String, previouslyClosedAt: Double?)
}
