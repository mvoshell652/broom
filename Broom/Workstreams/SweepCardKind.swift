/// The kinds of suggestion the weekly sweep makes, in the order it makes them.
public enum SweepCardKind: CaseIterable, Sendable {
    case merge, archive, revisit
}
