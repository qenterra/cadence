import Testing

/// Serializes tests that take ownership of AppKit's process-wide key window.
///
/// Swift Testing may execute unrelated suites concurrently. AppKit, however,
/// exposes one key window per process, so screenshot and keyboard tests must
/// share an explicit resource instead of racing to activate their own windows.
struct AppKitExclusiveTrait: TestTrait, TestScoping {
    func provideScope(
        for _: Test,
        testCase _: Test.Case?,
        performing function: @Sendable () async throws -> Void
    ) async throws {
        await AppKitTestGate.shared.acquire()
        do {
            try await function()
            await AppKitTestGate.shared.release()
        } catch {
            await AppKitTestGate.shared.release()
            throw error
        }
    }
}

extension Trait where Self == AppKitExclusiveTrait {
    static var appKitExclusive: Self {
        AppKitExclusiveTrait()
    }
}

private actor AppKitTestGate {
    static let shared = AppKitTestGate()

    private var isAcquired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isAcquired else {
            isAcquired = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard !waiters.isEmpty else {
            isAcquired = false
            return
        }

        waiters.removeFirst().resume()
    }
}
