import Foundation

/// One budget for all consumers, including visible screens and indexing. A
/// canceled consumer releases only its subscription, never another reader's work.
actor SharedLoadScheduler<Key: Hashable & Sendable, Value: Sendable> {
    private struct Job {
        let key: Key
        var priority: Int
        let order: Int
        let operation: @Sendable () async -> Value
        var subscribers: [UUID: CheckedContinuation<Value?, Never>]
        var task: Task<Void, Never>?
    }

    private let limit: Int
    private var jobs: [UUID: Job] = [:]
    private var keys: [Key: UUID] = [:]
    private var running = 0
    private var sequence = 0

    init(limit: Int) { self.limit = max(1, limit) }

    func value(for key: Key, priority: Int = 0,
               operation: @escaping @Sendable () async -> Value) async -> Value? {
        let subscriber = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return nil }
            return await withCheckedContinuation { continuation in
                if let id = keys[key], var job = jobs[id] {
                    job.subscribers[subscriber] = continuation
                    job.priority = max(job.priority, priority)
                    jobs[id] = job
                } else {
                    let id = UUID()
                    sequence += 1
                    jobs[id] = Job(key: key, priority: priority, order: sequence,
                                   operation: operation, subscribers: [subscriber: continuation])
                    keys[key] = id
                }
                startReadyJobs()
            }
        } onCancel: {
            Task { await self.cancel(subscriber: subscriber, key: key) }
        }
    }

    func subscriberCount(for key: Key) -> Int { keys[key].flatMap { jobs[$0]?.subscribers.count } ?? 0 }

    func cancelAll() {
        for (id, var job) in jobs {
            for continuation in job.subscribers.values { continuation.resume(returning: nil) }
            job.subscribers = [:]
            jobs[id] = job
            if let task = job.task { task.cancel() } else { jobs[id] = nil }
        }
        keys = [:]
    }

    private func cancel(subscriber: UUID, key: Key) {
        guard let id = keys[key], var job = jobs[id],
              let continuation = job.subscribers.removeValue(forKey: subscriber) else { return }
        continuation.resume(returning: nil)
        jobs[id] = job
        guard job.subscribers.isEmpty else { return }
        keys[key] = nil
        if let task = job.task {
            // Keep the occupied slot until the operation actually exits. Some
            // adapters cannot interrupt a request already handed to their SDK.
            task.cancel()
        } else {
            jobs[id] = nil
        }
        startReadyJobs()
    }

    private func startReadyJobs() {
        while running < limit {
            guard let next = jobs.filter({ $0.value.task == nil }).min(by: {
                if $0.value.priority != $1.value.priority { return $0.value.priority > $1.value.priority }
                return $0.value.order < $1.value.order
            }) else { return }
            let id = next.key
            let operation = next.value.operation
            running += 1
            jobs[id]?.task = Task {
                let value = await operation()
                self.finish(id, value: value)
            }
        }
    }

    private func finish(_ id: UUID, value: Value) {
        guard let job = jobs.removeValue(forKey: id) else { return }
        running -= 1
        if keys[job.key] == id { keys[job.key] = nil }
        for continuation in job.subscribers.values { continuation.resume(returning: value) }
        startReadyJobs()
    }
}
