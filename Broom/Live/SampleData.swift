import BroomCore
import Foundation

/// Made-up sessions for previews and for `Broom --render`.
enum SampleData {
    static let now = Date(timeIntervalSince1970: 1_794_650_400)

    static func session(
        _ id: String, _ state: LiveState, title: String, repo: String,
        started: TimeInterval, changed: TimeInterval,
        message: String? = nil, progress: StepProgress? = nil, snoozed: Bool = false, pid: Int32? = 100
    ) -> LiveSession {
        LiveSession(
            id: id, title: title, cwd: "/Users/dev/code/\(repo)", state: state,
            startedAt: now.addingTimeInterval(-started), lastActivityAt: now.addingTimeInterval(-changed),
            stateChangedAt: now.addingTimeInterval(-changed), waitingMessage: message, progress: progress,
            userTurns: 3, toolCalls: 12, pid: pid,
            snoozedUntil: snoozed ? now.addingTimeInterval(3600) : nil
        )
    }

    static let waiting = [
        session("w1", .waiting, title: "Store directory · Texas batch", repo: "scraper", started: 2400, changed: 360,
                message: "Found 42 stores. Add them all, or review the 9 with missing websites first?"),
    ]
    static let running = [
        session("r1", .running, title: "Scraper backfill", repo: "api-server", started: 1080, changed: 4,
                progress: StepProgress(completed: 6, total: 9)),
        session("r2", .running, title: "Recalibrate the projected-finish model", repo: "mobile", started: 7800, changed: 9),
        session("r3", .waiting, title: "Supabase tuning", repo: "mobile", started: 3000, changed: 900,
                message: "Permission needed for Bash", snoozed: true),
    ]
    static let done = [
        session("d1", .done, title: "Menu bar app design notes", repo: "Broom", started: 5000, changed: 240),
    ]
    static let quick = [
        session("q1", .quick, title: "5K pace to min/mile", repo: "dev", started: 1400, changed: 1320),
        session("q2", .quick, title: "SwiftUI .task vs .onAppear", repo: "dev", started: 3700, changed: 3600),
    ]
    static let scheduledTasks = [
        ScheduledTask(id: "s1", title: "Monday metrics digest", nextRunAt: now.addingTimeInterval(2 * 86_400)),
    ]

    static func sections(_ sessions: [LiveSession]) -> LiveSections {
        LiveSections(sessions: sessions, lastPopoverOpenedAt: now.addingTimeInterval(-3600), now: now)
    }

    static let everything = sections(waiting + running + done + quick)
    static let inbox: InboxContents = {
        func chat(_ id: String, _ title: String, hours: Double, folder: String = "api-server") -> IndexedChat {
            IndexedChat(
                id: id, title: title, hasCustomTitle: true, cwd: "/Users/dev/code/" + folder,
                startedAt: now.addingTimeInterval(-hours * 3600 - 600), lastActivityAt: now.addingTimeInterval(-hours * 3600),
                transcriptPath: "/tmp/" + id
            )
        }
        return InboxContents(
            duplicates: [DuplicateGroup(kind: .similar, chats: [
                chat("d1", "Supabase RLS policies for teams", hours: 30), chat("d2", "RLS for team tables", hours: 200),
                chat("d3", "Team row level security", hours: 550),
            ])],
            openLoops: [
                OpenLoop(chat: chat("l1", "Decide: BYO API key vs bundled labeling", hours: 48), kind: .question, workstreamName: "Broom"),
                OpenLoop(chat: chat("l2", "Send vendor follow-ups", hours: 120), kind: .deferred("I’ll do this tomorrow"), workstreamName: "Partnerships"),
            ]
        )
    }()
    static let workstreams: [WorkstreamGroup] = [
        ("api-server", ["Search ranking v2 scoring", "rank_score() migration", "RLS policies for orders"]),
        ("mobile", ["Onboarding flow copy", "Flaky test triage"]),
        ("planning", ["Ranking explainer for the blog"]),
    ].enumerated().map { index, entry in
        WorkstreamGroup(
            workstream: Workstream(id: Int64(index + 1), name: entry.0),
            chats: entry.1.enumerated().map { position, title in
                IndexedChat(
                    id: "\(entry.0)-\(position)", title: title, hasCustomTitle: true, cwd: "/Users/dev/code/" + entry.0,
                    lastActivityAt: now.addingTimeInterval(-Double(index * 3 + position + 1) * 5400), transcriptPath: "/tmp/\(entry.0)-\(position)"
                )
            }
        )
    }
    static let sweepCards: [SweepCard] = inbox.duplicates.map(SweepCard.merge)
        + [.archive(workstream: workstreams[1].workstream, chats: workstreams[1].chats)]
        + inbox.openLoops.map(SweepCard.revisit)
    static let history: [HistoryItem] = {
        let chats = Dictionary(uniqueKeysWithValues: (workstreams.flatMap(\.chats) + inbox.openLoops.map(\.chat)).map { ($0.id, $0) })
        return [
            OrganizerLogEntry(id: 3, summary: "", change: .closedLoop(chatID: "l2", previouslyClosedAt: nil), date: now.addingTimeInterval(-1800)),
            OrganizerLogEntry(id: 2, summary: "", change: .merged(previousGroups: ["mobile-0": nil, "mobile-1": nil]), date: now.addingTimeInterval(-7200)),
            OrganizerLogEntry(id: 1, summary: "", change: .archived(chatIDs: ["api-server-1", "api-server-2"]), date: now.addingTimeInterval(-90_000)),
        ].map { HistoryItem(entry: $0, chatsByID: chats) }
    }()
    static let quietProcesses = QuietProcesses(
        sessions: [session("i1", .idle, title: "Old migration notes", repo: "api-server", started: 30_000, changed: 12_000)],
        unmatchedProcesses: [ClaudeProcess(pid: 4321, cwd: "/Users/dev/code/scratch", startedAt: now.addingTimeInterval(-90_000))],
        now: now
    )
    static let empty = sections([])
}
