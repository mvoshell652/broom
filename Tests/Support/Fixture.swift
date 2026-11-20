import Foundation
@testable import BroomCore

/// Loads the transcripts in `Tests/Fixtures`.
enum Fixture: String, CaseIterable {
    case running
    case waitingPermission = "waiting-permission"
    case waitingQuestion = "waiting-question"
    case done
    case quick
    case malformed
    case progressTodoWrite = "progress-todowrite"
    case progressTasks = "progress-tasks"

    var data: Data {
        get throws {
            guard let url = Bundle.module.url(forResource: rawValue, withExtension: "jsonl", subdirectory: "Fixtures") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try Data(contentsOf: url)
        }
    }

    /// The digest after parsing the whole file in one chunk.
    var digest: TranscriptDigest {
        get throws {
            var parser = TranscriptParser()
            try parser.consume(data)
            return parser.digest
        }
    }
}
