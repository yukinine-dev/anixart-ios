import Foundation

/// A deadline, not a minimum display time. The losing work is cancelled without
/// awaiting it: a task group would still wait for an uncooperative async store or
/// callback and could leave the launch screen up forever. Tests inject the clock.
struct AppLaunchDeadline: Sendable {
    private let sleep: @Sendable (Duration) async throws -> Void

    init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    func run<Value: Sendable>(
        for timeout: Duration,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let race = AppLaunchDeadlineRace<Value>()
        let sleep = self.sleep
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard race.install(continuation) else { return }
                let work = Task {
                    do {
                        try Task.checkCancellation()
                        let value = try await operation()
                        try Task.checkCancellation()
                        race.finish(.success(value))
                    } catch { race.finish(.failure(error)) }
                }
                let timer = Task {
                    do {
                        try await sleep(timeout)
                        try Task.checkCancellation()
                        race.finish(.failure(URLError(.timedOut)))
                    } catch {
                        if !Task.isCancelled { race.finish(.failure(error)) }
                    }
                }
                race.retain(work, timer)
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }
}

/// Continuations and task handles can be installed after cancellation/completion.
/// The lock gives every ordering exactly one result and cancels late handles too.
private final class AppLaunchDeadlineRace<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var earlyResult: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var tasks: [Task<Void, Never>] = []

    func install(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        if let result = earlyResult {
            earlyResult = nil
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func retain(_ work: Task<Void, Never>, _ timer: Task<Void, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            work.cancel()
            timer.cancel()
        } else {
            tasks = [work, timer]
            lock.unlock()
        }
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        if continuation == nil { earlyResult = result }
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()
        for task in tasks { task.cancel() }
        continuation?.resume(with: result)
    }
}
