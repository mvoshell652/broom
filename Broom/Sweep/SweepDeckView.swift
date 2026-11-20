import BroomCore
import SwiftUI

/// The Inbox while a sweep is in progress: how far through it is, and the card on top.
struct SweepDeckView: View {
    let deck: SweepDeck
    let card: SweepCard
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SweepProgressHeader(position: deck.position + 1, count: deck.cards.count)
            SweepCardPanel(card: card, now: now)
                .id(card.id)
        }
        .padding(.horizontal, BroomStyle.gutter)
        .padding(.bottom, BroomStyle.gutter)
    }
}
