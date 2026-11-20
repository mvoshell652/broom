import BroomCore
import Foundation

extension ClaudeProcess {
    /// The last component of the process's working directory.
    var folderName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}
