/// The popover's tabs, in the order the tab strip shows them. Inbox leads because clean-up is what Broom is for.
enum PopoverTab: Hashable, CaseIterable {
    case inbox, live, history
}
