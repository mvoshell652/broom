import BroomCore

/// A sweep in progress: the cards it began with and how far through them the user is.
struct SweepDeck: Equatable {
    let cards: [SweepCard]
    var position = 0

    /// The card on top, or `nil` when the deck is finished.
    var current: SweepCard? {
        cards.indices.contains(position) ? cards[position] : nil
    }
}
