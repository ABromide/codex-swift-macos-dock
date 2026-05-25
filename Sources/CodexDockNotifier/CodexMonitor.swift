import CodexDockNotifierCore
import Foundation

final class CodexMonitor: @unchecked Sendable {
    private let sessionsDirectory: URL
    private let sessionIndexFile: URL
    private let stateFile: URL
    private let onCompletion: (CodexCompletion) -> Void
    private let queue = DispatchQueue(label: "CodexDockNotifier.Monitor", qos: .utility)

    private var timer: DispatchSourceTimer?
    private var state: WatchState
    private var notifiedKeys: Set<String>
    private var threadNames: [String: String] = [:]
    private var lastIndexModificationDate: Date?
    private let hasExistingState: Bool
    private var stateDirty = false

    init(
        sessionsDirectory: URL = CodexDefaultPaths.sessionsDirectory,
        sessionIndexFile: URL = CodexDefaultPaths.sessionIndexFile,
        stateFile: URL = CodexDefaultPaths.stateFile,
        onCompletion: @escaping (CodexCompletion) -> Void
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.sessionIndexFile = sessionIndexFile
        self.stateFile = stateFile
        self.onCompletion = onCompletion
        self.hasExistingState = FileManager.default.fileExists(atPath: stateFile.path)

        let loadedState = WatchState.load(from: stateFile)
        self.state = loadedState
        self.notifiedKeys = Set(loadedState.notifiedKeys)
    }

    func start() {
        queue.async {
            self.reloadSessionIndexIfNeeded(force: true)
            self.scan(notify: self.hasExistingState)
            self.saveStateIfNeeded(force: true)

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
            timer.setEventHandler { [weak self] in
                self?.scan(notify: true)
            }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            saveStateIfNeeded(force: true)
        }
    }

    func scanNow() {
        queue.async {
            self.scan(notify: true)
        }
    }

    func completionHistory() -> [CodexCompletion] {
        queue.sync {
            state.completionHistory
        }
    }

    private func scan(notify: Bool) {
        reloadSessionIndexIfNeeded(force: false)

        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            processFile(at: url, notify: notify)
        }

        saveStateIfNeeded()
    }

    private func processFile(at url: URL, notify: Bool) {
        let path = url.path

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let fileSize = attributes[.size] as? UInt64
        else {
            return
        }

        if state.cursors[path] == nil {
            state.cursors[path] = FileCursor(offset: notify ? 0 : fileSize)
            stateDirty = true
        }

        guard var cursor = state.cursors[path] else {
            return
        }

        if fileSize < cursor.offset {
            cursor.offset = 0
        }

        guard fileSize > cursor.offset else {
            if state.cursors[path] != cursor {
                state.cursors[path] = cursor
                stateDirty = true
            }
            return
        }

        guard let data = readData(from: url, offset: cursor.offset), !data.isEmpty else {
            if state.cursors[path] != cursor {
                state.cursors[path] = cursor
                stateDirty = true
            }
            return
        }

        var consumedOffset = cursor.offset
        var currentIndex = data.startIndex

        while currentIndex < data.endIndex,
              let newlineIndex = data[currentIndex...].firstIndex(of: 0x0A) {
            let lineStartOffset = consumedOffset
            let lineData = data[currentIndex..<newlineIndex]
            consumedOffset += UInt64(lineData.count + 1)
            currentIndex = data.index(after: newlineIndex)

            guard !lineData.isEmpty,
                  let line = String(data: lineData, encoding: .utf8),
                  var completion = CodexCompletionParser.parseCompletionLine(
                    line,
                    filePath: path,
                    lineOffset: lineStartOffset
                  )
            else {
                continue
            }

            if let threadID = completion.threadID {
                completion.threadName = threadNames[threadID]
            }

            handle(completion, notify: notify)
        }

        cursor.offset = consumedOffset
        if state.cursors[path] != cursor {
            state.cursors[path] = cursor
            stateDirty = true
        }
    }

    private func handle(_ completion: CodexCompletion, notify: Bool) {
        guard !notifiedKeys.contains(completion.key) else {
            return
        }

        notifiedKeys.insert(completion.key)
        if notifiedKeys.count > 1_000 {
            notifiedKeys = Set(notifiedKeys.suffix(800))
        }
        state.notifiedKeys = Array(notifiedKeys).sorted()
        stateDirty = true

        guard notify else {
            return
        }

        recordCompletionInHistory(completion)
        onCompletion(completion)
    }

    private func recordCompletionInHistory(_ completion: CodexCompletion) {
        state.completionHistory.removeAll { $0.key == completion.key }
        state.completionHistory.insert(completion, at: 0)
        if state.completionHistory.count > 200 {
            state.completionHistory = Array(state.completionHistory.prefix(200))
        }
        stateDirty = true
    }

    private func readData(from url: URL, offset: UInt64) -> Data? {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }

            try handle.seek(toOffset: offset)
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }

    private func reloadSessionIndexIfNeeded(force: Bool) {
        let modificationDate = (try? FileManager.default
            .attributesOfItem(atPath: sessionIndexFile.path)[.modificationDate]) as? Date

        guard force || modificationDate != lastIndexModificationDate else {
            return
        }

        threadNames = CodexSessionIndex.loadThreadNames(from: sessionIndexFile)
        lastIndexModificationDate = modificationDate
    }

    private func saveStateIfNeeded(force: Bool = false) {
        guard force || stateDirty else {
            return
        }

        do {
            state.notifiedKeys = Array(notifiedKeys).sorted()
            try state.save(to: stateFile)
            stateDirty = false
        } catch {
            NSLog("CodexDockNotifier failed to save state: \(error)")
        }
    }
}
