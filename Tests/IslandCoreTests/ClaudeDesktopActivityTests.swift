import XCTest

@testable import IslandCore

final class ClaudeDesktopActivityTests: XCTestCase {
    private typealias Node = V8Fixture.Node
    private var temporary: [URL] = []

    override func tearDown() {
        for url in temporary { try? FileManager.default.removeItem(at: url) }
        temporary = []
    }

    func testAgentKind() {
        XCTAssertEqual(AgentKind.claudeDesktop.rawValue, "claude-desktop")
        XCTAssertEqual(AgentKind.claudeDesktop.displayName, "Claude")
        XCTAssertEqual(AgentKind.claudeDesktop.processNames, ["Claude"])
    }

    /// Issue claude-desktop-source: a reply that ended with `end_turn` is a
    /// finished run, titled from the conversation list, and links back to the
    /// conversation.
    func testAFinishedReplyBecomesATask() throws {
        let tasks = ClaudeDesktopActivitySource.tasks(
            from: try decoded(
                cache(
                    conversations: [("c-1", "N8n 对比")],
                    transcripts: [
                        (
                            "c-1",
                            [
                                message("human", text: "compare n8n"),
                                message(
                                    "assistant", stop: "end_turn", at: "2026-09-25T21:47:52.937Z"),
                            ]
                        )
                    ])))

        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(task.agent, .claudeDesktop)
        XCTAssertEqual(task.sessionID, "c-1")
        XCTAssertEqual(task.title, "N8n 对比")
        XCTAssertNil(task.cwd)
        XCTAssertEqual(task.completedAt, AgentTimestamp.date(from: "2026-09-25T21:47:52.937Z"))
        XCTAssertEqual(task.host, .desktop(bundleID: "com.anthropic.claudefordesktop"))
        XCTAssertNil(task.resumeCommand)
        XCTAssertEqual(task.deepLink, "claude://claude.ai/chat/c-1")
    }

    /// Stopping a reply (`user_canceled`), a reply still streaming (the last
    /// message is the user's) and an empty transcript are not finished runs.
    func testUnfinishedRepliesAreSkipped() throws {
        let tasks = ClaudeDesktopActivitySource.tasks(
            from: try decoded(
                cache(
                    conversations: [],
                    transcripts: [
                        (
                            "stopped",
                            [
                                message(
                                    "assistant", stop: "user_canceled", at: "2026-09-25T21:49:11Z")
                            ]
                        ),
                        ("waiting", [message("human", text: "hi")]),
                        ("empty", []),
                        ("untimed", [message("assistant", stop: "end_turn", at: nil)]),
                    ])))

        XCTAssertEqual(tasks, [])
    }

    func testTitleFallsBackToTheLastUserMessage() throws {
        let tasks = ClaudeDesktopActivitySource.tasks(
            from: try decoded(
                cache(
                    conversations: [("other", "Other")],
                    transcripts: [
                        (
                            "c-2",
                            [
                                message("human", text: "first"),
                                message(
                                    "human",
                                    blocks: [
                                        .obj([("type", .str("image"))]),
                                        .obj([("type", .str("text")), ("text", .wide("最后一问"))]),
                                    ]),
                                message("assistant", stop: "end_turn", at: "2026-09-25T21:00:00Z"),
                            ]
                        ),
                        (
                            "c-3",
                            [message("assistant", stop: "end_turn", at: "2026-09-25T21:00:01Z")]
                        ),
                    ])))

        XCTAssertEqual(tasks.map(\.title), ["最后一问", "(untitled)"])
    }

    func testIgnoresQueriesItDoesNotKnowAndMalformedOnes() throws {
        let root: Node = .obj([
            ("buster", .str("conversations_v2:1")),
            (
                "clientState",
                .obj([
                    (
                        "queries",
                        .sparse([
                            .obj([
                                ("queryKey", .sparse([.str("current_account")])),
                                ("state", .obj([])),
                            ]),
                            .obj([
                                (
                                    "queryKey",
                                    .sparse([.str("hub_transcript"), .obj([]), .obj([])])
                                ), ("state", .obj([])),
                            ]),
                            // A transcript with no data yet.
                            .obj([
                                (
                                    "queryKey",
                                    .sparse([
                                        .str("hub_transcript"), .obj([]),
                                        .obj([("uuid", .str("u"))]),
                                    ])
                                ), ("state", .obj([])),
                            ]),
                            // Conversation lists with a page missing `data`, and
                            // with no data at all.
                            .obj([
                                ("queryKey", .sparse([.str("chat_conversation_list")])),
                                ("state", .obj([("data", .obj([("pages", .sparse([.obj([])]))]))])),
                            ]),
                            .obj([
                                ("queryKey", .sparse([.str("chat_conversation_list")])),
                                ("state", .obj([])),
                            ]),
                            .obj([("state", .obj([]))]),
                            .str("junk"),
                        ])
                    )
                ])
            ),
        ])

        XCTAssertEqual(
            ClaudeDesktopActivitySource.tasks(from: try decoded(Array(V8Fixture.blob(root)))), [])
        XCTAssertEqual(ClaudeDesktopActivitySource.tasks(from: .null), [])
    }

    func testDecodesUncompressedAndRejectsGarbage() throws {
        let value = V8Fixture.encode(.obj([("a", .int(1))]))
        let envelope: [UInt8] = [0xFF, 0x15, 0xFF, 0x10]

        XCTAssertEqual(ClaudeDesktopActivitySource.decode(envelope + value)?["a"], .number(1))
        XCTAssertNil(ClaudeDesktopActivitySource.decode([]))
        XCTAssertNil(ClaudeDesktopActivitySource.decode([0xFF, 0x11, 0x02, 0x80]))  // bad snappy
        XCTAssertNil(ClaudeDesktopActivitySource.decode([0x01, 0x02, 0x03, 0x04]))  // no V8 header
    }

    func testCompletedTasksReadsTheNewestBlob() throws {
        let root = try makeTempDirectory()
        let folder = root.appendingPathComponent("1/94")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = folder.appendingPathComponent("1944f")
        let new = folder.appendingPathComponent("19450")
        try V8Fixture.blob(cache(conversations: [], transcripts: [])).write(to: old)
        try V8Fixture.blob(
            cache(
                conversations: [("c", "Latest")],
                transcripts: [
                    ("c", [message("assistant", stop: "end_turn", at: "2026-09-25T21:00:00Z")])
                ])
        ).write(to: new)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: new.path)
        let source = ClaudeDesktopActivitySource(blobRoot: root)

        XCTAssertEqual(source.completedTasks().map(\.title), ["Latest"])
        // Served from the cache the second time; same answer.
        XCTAssertEqual(source.completedTasks().map(\.title), ["Latest"])

        try Data("garbage".utf8).write(to: new)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 300)], ofItemAtPath: new.path)
        XCTAssertEqual(source.completedTasks(), [])
    }

    func testCompletedTasksWithoutTheAppInstalled() throws {
        let root = try makeTempDirectory().appendingPathComponent("missing")

        XCTAssertEqual(ClaudeDesktopActivitySource(blobRoot: root).completedTasks(), [])
        XCTAssertEqual(ClaudeDesktopActivitySource.standard(home: root).completedTasks(), [])
    }

    // MARK: - Fixtures

    private func decoded(_ root: Node) throws -> V8Value {
        try decoded(Array(V8Fixture.blob(root)))
    }

    private func decoded(_ bytes: [UInt8]) throws -> V8Value {
        try XCTUnwrap(ClaudeDesktopActivitySource.decode(bytes))
    }

    private func message(
        _ sender: String, text: String? = nil, blocks: [Node]? = nil, stop: String? = nil,
        at timestamp: String? = nil
    ) -> Node {
        var pairs: [(String?, Node)] = [("sender", .str(sender))]
        let content =
            blocks ?? text.map { [.obj([("type", .str("text")), ("text", .str($0))])] } ?? []
        pairs.append(("content", .sparse(content)))
        pairs.append(("stop_reason", stop.map(Node.str) ?? .null))
        if let timestamp { pairs.append(("updated_at", .str(timestamp))) }
        return .obj(pairs)
    }

    /// The shape of the react-query cache the desktop app persists.
    private func cache(conversations: [(String, String)], transcripts: [(String, [Node])]) -> Node {
        let list: Node = .obj([
            ("queryKey", .sparse([.str("chat_conversation_list"), .obj([]), .str("infinite")])),
            (
                "state",
                .obj([
                    (
                        "data",
                        .obj([
                            (
                                "pages",
                                // Each page is `{data: [...], has_more, …}`, as the
                                // desktop app caches it.
                                .sparse([
                                    .obj([
                                        (
                                            "data",
                                            .sparse(
                                                conversations.map { uuid, name in
                                                    .obj([
                                                        ("uuid", .str(uuid)), ("name", .wide(name)),
                                                    ])
                                                })
                                        ),
                                        ("has_more", .bool(false)),
                                    ])
                                ])
                            )
                        ])
                    )
                ])
            ),
        ])
        let starred: Node = .obj([
            ("queryKey", .sparse([.str("chat_conversation_list"), .obj([]), .obj([])])),
            (
                "state",
                .obj([
                    (
                        "data",
                        .obj([
                            (
                                "data",
                                .sparse([.obj([("uuid", .str("s")), ("name", .str("Starred"))])])
                            )
                        ])
                    )
                ])
            ),
        ])
        let hubs: [Node] = transcripts.map { uuid, messages in
            .obj([
                (
                    "queryKey",
                    .sparse([.str("hub_transcript"), .obj([]), .obj([("uuid", .str(uuid))])])
                ),
                ("state", .obj([("data", .obj([("messages", .sparse(messages))]))])),
            ])
        }
        return .obj([
            ("buster", .str("conversations_v2:1")),
            ("clientState", .obj([("queries", .sparse([list, starred] + hubs))])),
        ])
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-desktop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporary.append(url)
        return url
    }
}
