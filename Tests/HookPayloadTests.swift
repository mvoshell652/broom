import Foundation
import Testing
@testable import BroomCore

@Suite("HookPayload")
struct HookPayloadTests {
    private func signal(_ body: String) throws -> SessionSignal? {
        let json = #"{"session_id":"s1","transcript_path":"/t/s1.jsonl","cwd":"/work/repo","permission_mode":"default",\#(body)}"#
        let payload = try JSONDecoder().decode(HookPayload.self, from: Data(json.utf8))
        return payload.sessionEvent(receivedAt: TestClock.start)?.signal
    }

    /// The tail of a payload body and the signal it must map to.
    struct Mapping: Sendable, CustomTestStringConvertible {
        var name: String
        var body: String
        var expected: SessionSignal

        var testDescription: String { name }
    }

    private static let mappings = [
        Mapping(name: "SessionStart with a source and title",
                body: #""hook_event_name":"SessionStart","source":"resume","session_title":"My title""#,
                expected: .sessionStarted(source: .resume, title: "My title")),
        Mapping(name: "SessionStart with an unknown source",
                body: #""hook_event_name":"SessionStart","source":"something-new""#,
                expected: .sessionStarted(source: .startup, title: nil)),
        Mapping(name: "UserPromptSubmit",
                body: #""hook_event_name":"UserPromptSubmit","prompt":"Fix the bug""#,
                expected: .promptSubmitted(prompt: "Fix the bug", title: nil)),
        Mapping(name: "PreToolUse",
                body: #""hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"},"tool_use_id":"t1""#,
                expected: .toolActivity(.started)),
        Mapping(name: "PostToolUse",
                body: #""hook_event_name":"PostToolUse","tool_name":"Bash","tool_response":{"ok":true}"#,
                expected: .toolActivity(.finished)),
        Mapping(name: "PostToolUseFailure",
                body: #""hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"exit 1""#,
                expected: .toolActivity(.failed)),
        Mapping(name: "PermissionRequest",
                body: #""hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build"}"#,
                expected: .permissionRequested(toolName: "Bash")),
        Mapping(name: "Stop",
                body: #""hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"Done.""#,
                expected: .stopped),
        Mapping(name: "StopFailure",
                body: #""hook_event_name":"StopFailure","error":"rate_limit""#,
                expected: .stopFailed(error: "rate_limit")),
        Mapping(name: "SessionEnd",
                body: #""hook_event_name":"SessionEnd","reason":"prompt_input_exit""#,
                expected: .sessionEnded),
    ]

    @Test("Each tracked hook event maps to its signal", arguments: mappings)
    func mapping(_ mapping: Mapping) throws {
        #expect(try signal(mapping.body) == mapping.expected)
    }

    @Test("Notification types that mean waiting", arguments: [
        "permission_prompt", "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog",
    ])
    func waitingNotificationTypes(type: String) throws {
        let mapped = try signal(#""hook_event_name":"Notification","message":"Claude needs your permission","notification_type":"\#(type)""#)

        #expect(mapped == .notification(.needsUser, message: "Claude needs your permission"))
    }

    @Test("idle_prompt is its own kind")
    func idlePrompt() throws {
        let mapped = try signal(#""hook_event_name":"Notification","message":"Claude is waiting for your input","notification_type":"idle_prompt""#)

        #expect(mapped == .notification(.idlePrompt, message: "Claude is waiting for your input"))
    }

    @Test("Other notification types are informational", arguments: [
        "auth_success", "agent_completed", "elicitation_complete", "quota_auto_resume_fired", "plugin_notification", "a_future_type",
    ])
    func informationalNotificationTypes(type: String) throws {
        let mapped = try signal(#""hook_event_name":"Notification","message":"FYI","notification_type":"\#(type)""#)

        #expect(mapped == .notification(.informational, message: "FYI"))
    }

    @Test("A notification with no type is informational")
    func untypedNotification() throws {
        #expect(try signal(#""hook_event_name":"Notification","message":"Claude needs your permission""#)
            == .notification(.informational, message: "Claude needs your permission"))
    }

    @Test("Any event fired inside a subagent is subagent activity", arguments: [
        "PreToolUse", "PostToolUse", "PermissionRequest", "SubagentStop", "Notification",
    ])
    func subagentEvents(event: String) throws {
        #expect(try signal(#""hook_event_name":"\#(event)","agent_id":"agent-7","agent_type":"Explore""#)
            == .subagentActivity)
    }

    @Test("Untracked events map to nothing", arguments: ["PreCompact", "SubagentStop", "ConfigChange", "FutureEvent"])
    func untrackedEvents(event: String) throws {
        #expect(try signal(#""hook_event_name":"\#(event)""#) == nil)
    }

    @Test("The event carries the session id, cwd and transcript path")
    func eventFields() throws {
        let json = #"{"session_id":"s1","transcript_path":"/t/s1.jsonl","cwd":"/work/repo","hook_event_name":"Stop"}"#
        let payload = try JSONDecoder().decode(HookPayload.self, from: Data(json.utf8))

        let event = try #require(payload.sessionEvent(receivedAt: TestClock.at(5)))

        #expect(event == SessionEvent(
            sessionID: "s1", date: TestClock.at(5), signal: .stopped, cwd: "/work/repo", transcriptPath: "/t/s1.jsonl"
        ))
    }

    @Test("A payload without a session id does not decode")
    func missingSessionID() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(HookPayload.self, from: Data(#"{"hook_event_name":"Stop"}"#.utf8))
        }
    }
}
