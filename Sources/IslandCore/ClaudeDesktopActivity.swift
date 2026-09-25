import Foundation

/// Claude Desktop keeps chats on the server; the only local trace is the
/// claude.ai front end's react-query cache, which Chromium persists into an
/// IndexedDB blob file (snappy-compressed V8 value) a few seconds after every
/// change. Each persist writes a new file, so the newest one is the state.
///
/// A conversation's cached transcript ends with an assistant message whose
/// `stop_reason` is `end_turn` once the reply finished; stopping a reply
/// leaves `user_canceled` instead. Only conversations the app has open (or
/// had open recently) carry a transcript.
public struct ClaudeDesktopActivitySource: AgentActivitySource {
    public let agent = AgentKind.claudeDesktop

    static let bundleID = "com.anthropic.claudefordesktop"

    private let blobRoot: URL
    private let cache = ClaudeDesktopCacheReader()

    public init(blobRoot: URL) {
        self.blobRoot = blobRoot
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ClaudeDesktopActivitySource {
        ClaudeDesktopActivitySource(
            blobRoot: home.appendingPathComponent(
                "Library/Application Support/Claude/IndexedDB/https_claude.ai_0.indexeddb.blob"))
    }

    public func completedTasks() -> [AgentTask] {
        // Blob files live at `<database>/<two hex digits>/<blob id>`.
        let files = AgentFiles.directoryContents(blobRoot)
            .flatMap(AgentFiles.directoryContents)
            .flatMap(AgentFiles.directoryContents)
        guard
            let newest = files.max(by: {
                PiActivitySource.modifiedAt($0) < PiActivitySource.modifiedAt($1)
            }),
            let value = cache.value(at: newest)
        else { return [] }
        return Self.tasks(from: value)
    }

    /// Unwraps Chromium's IndexedDB value: an optional snappy wrapper
    /// (`ff 11 02`), then Blink's envelope, then the V8 value itself.
    static func decode(_ bytes: [UInt8]) -> V8Value? {
        var payload = bytes
        if bytes.starts(with: [0xFF, 0x11, 0x02]) {
            guard let inflated = Snappy.decompress(Array(bytes.dropFirst(3))) else { return nil }
            payload = inflated
        }
        // The V8 header is `ff <version>` directly followed by the root value;
        // Blink's own `ff <version> fe …` header in front of it is skipped.
        let roots: Set<UInt8> = [UInt8(ascii: "o"), UInt8(ascii: "A"), UInt8(ascii: "a")]
        for index in payload.indices.prefix(64) where payload[index] == 0xFF {
            guard index + 2 < payload.count, roots.contains(payload[index + 2]) else { continue }
            return V8Value.decode(Array(payload[index...]))
        }
        return nil
    }

    static func tasks(from cache: V8Value) -> [AgentTask] {
        let queries = cache["clientState"]?["queries"]?.elements ?? []
        let names = conversationNames(in: queries)
        return queries.compactMap { query -> AgentTask? in
            let key = query["queryKey"]?.elements ?? []
            guard key.first?.string == "hub_transcript",
                let uuid = key.dropFirst(2).first?["uuid"]?.string
            else { return nil }
            let messages = query["state"]?["data"]?["messages"]?.elements ?? []
            guard let last = messages.last,
                last["sender"]?.string == "assistant",
                last["stop_reason"]?.string == "end_turn",
                let completedAt = last["updated_at"]?.string.flatMap(AgentTimestamp.date(from:))
            else { return nil }
            let lastPrompt = messages.last { $0["sender"]?.string == "human" }
                .flatMap { firstText(in: $0["content"]) }
            return AgentTask(
                agent: .claudeDesktop,
                sessionID: uuid,
                title: TaskTitle.resolve(title: names[uuid], lastMessage: lastPrompt, cwd: nil),
                cwd: nil,
                completedAt: completedAt,
                host: .desktop(bundleID: bundleID),
                resumeCommand: nil,
                deepLink: "claude://claude.ai/chat/\(uuid)"
            )
        }
    }

    /// Conversation titles from every cached `chat_conversation_list`, both
    /// the paged (`pages`) and the plain (`data`) shapes.
    private static func conversationNames(in queries: [V8Value]) -> [String: String] {
        var names: [String: String] = [:]
        for query in queries
        where query["queryKey"]?.elements.first?.string == "chat_conversation_list" {
            let data = query["state"]?["data"]
            // Paged queries hold `pages: [{data: [...]}]`; plain ones `data: [...]`.
            let lists =
                data?["pages"]?.elements.map { $0["data"] ?? .null } ?? [data?["data"] ?? .null]
            for conversation in lists.flatMap(\.elements) {
                if let uuid = conversation["uuid"]?.string, let name = conversation["name"]?.string
                {
                    names[uuid] = name
                }
            }
        }
        return names
    }

    private static func firstText(in content: V8Value?) -> String? {
        content?.elements.lazy
            .filter { $0["type"]?.string == "text" }
            .compactMap { $0["text"]?.string }
            .first { !$0.isEmpty }
    }
}

/// The cache file is a megabyte or more and is polled every few seconds, so it
/// is decoded again only when a different file or modification date shows up.
final class ClaudeDesktopCacheReader: @unchecked Sendable {
    private let lock = NSLock()
    private var last: (path: String, modified: Date, value: V8Value?)?

    func value(at url: URL) -> V8Value? {
        let modified = PiActivitySource.modifiedAt(url)
        lock.lock()
        defer { lock.unlock() }
        if let last, last.path == url.path, last.modified == modified { return last.value }
        let value = (try? Data(contentsOf: url)).flatMap {
            ClaudeDesktopActivitySource.decode(Array($0))
        }
        last = (url.path, modified, value)
        return value
    }
}
