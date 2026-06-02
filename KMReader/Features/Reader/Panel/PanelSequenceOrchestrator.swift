//
// PanelSequenceOrchestrator.swift
//
//

import CoreGraphics
import Foundation

/// Drives panel detection lazily, cancellably, and stale-safely, writing results into
/// a `PanelSequenceCache`. Eager for the current page (the engage precondition), lazy
/// lookahead for neighbors, cancellable on page flip and mode exit.
///
/// Concurrency contract: a cancelled `detect` resolves to `.empty`, indistinguishable
/// from a genuine "no panels" result — so a cancelled/superseded task's result is
/// **never** written to the cache (that would poison the page with a false `.empty`).
@MainActor
final class PanelSequenceOrchestrator {
    private struct PageToken: Hashable {
        let bookId: String
        let pageNumber: Int
    }

    private struct InFlight {
        let id: Int
        let task: Task<PanelSequence, Never>
    }

    private let provider: any PanelDetectionProvider
    private let cache: PanelSequenceCache
    private let loader: any PanelImageLoading

    private var inFlight: [PageToken: InFlight] = [:]
    private var nextRequestId = 0

    init(
        provider: any PanelDetectionProvider,
        cache: PanelSequenceCache = PanelSequenceCache(),
        loader: any PanelImageLoading = PanelPageImageLoader()
    ) {
        self.provider = provider
        self.cache = cache
        self.loader = loader
    }

    /// In-flight detection count — diagnostics / debug harness only.
    var inFlightCount: Int { inFlight.count }

    /// Cache hit, else eager compute (awaited). The precondition for engage.
    func sequence(bookId: String, page: BookPage, direction: ReadingDirection) async -> PanelSequence {
        let key = makeKey(bookId: bookId, page: page, direction: direction)
        if let cached = await cache.sequence(for: key.fingerprint) { return cached }
        return await task(for: bookId, page: page, direction: direction, priority: .userInitiated).value
    }

    /// Kick off detection without awaiting (lazy lookahead / pre-warm).
    func prewarm(bookId: String, page: BookPage, direction: ReadingDirection, priority: TaskPriority = .utility) {
        _ = task(for: bookId, page: page, direction: direction, priority: priority)
    }

    /// Eager-warm the current page and lazy-warm its neighbors; cancel anything that
    /// fell outside the new window (different book or page no longer adjacent).
    func handlePageChange(
        bookId: String,
        currentPage: BookPage,
        adjacentPages: [BookPage],
        direction: ReadingDirection
    ) {
        let window = Set([currentPage.number] + adjacentPages.map(\.number))
        for (token, entry) in inFlight where token.bookId != bookId || !window.contains(token.pageNumber) {
            entry.task.cancel()
            inFlight[token] = nil
        }

        prewarm(bookId: bookId, page: currentPage, direction: direction, priority: .userInitiated)
        for page in adjacentPages {
            prewarm(bookId: bookId, page: page, direction: direction, priority: .utility)
        }
    }

    /// Cancel and forget every in-flight detection (mode exit).
    func cancelAll() {
        for entry in inFlight.values { entry.task.cancel() }
        inFlight.removeAll()
    }

    // MARK: - Private

    /// The single in-flight task per page — de-duplicates concurrent requests.
    private func task(
        for bookId: String,
        page: BookPage,
        direction: ReadingDirection,
        priority: TaskPriority
    ) -> Task<PanelSequence, Never> {
        let token = PageToken(bookId: bookId, pageNumber: page.number)
        if let existing = inFlight[token] { return existing.task }

        nextRequestId += 1
        let id = nextRequestId
        let work = Task(priority: priority) { [weak self] () -> PanelSequence in
            guard let self else { return .empty }
            let result = await self.compute(bookId: bookId, page: page, direction: direction)
            self.clearSlot(token: token, id: id)
            return result
        }
        inFlight[token] = InFlight(id: id, task: work)
        return work
    }

    /// Clear the in-flight slot only if it is still the task we created (not a newer one).
    private func clearSlot(token: PageToken, id: Int) {
        if inFlight[token]?.id == id { inFlight[token] = nil }
    }

    private func compute(bookId: String, page: BookPage, direction: ReadingDirection) async -> PanelSequence {
        let key = makeKey(bookId: bookId, page: page, direction: direction)
        if let cached = await cache.sequence(for: key.fingerprint) { return cached }

        guard let image = await loader.pageImage(bookId: bookId, page: page) else {
            // Transient load failure → show whole, but do NOT cache (retry next time).
            return .empty
        }

        let sequence = await provider.detect(image: image, direction: direction)

        // Drop a cancelled/superseded result: a cancelled detect resolves to `.empty`,
        // which must never be cached as a genuine "no panels".
        guard !Task.isCancelled else { return .empty }

        await cache.store(sequence, for: key.fingerprint)
        return sequence
    }

    private func makeKey(bookId: String, page: BookPage, direction: ReadingDirection) -> PanelCacheKey {
        PanelCacheKey(
            instanceId: CacheNamespace.identifier(),
            bookId: bookId,
            page: page,
            detectorVersion: provider.version,
            direction: direction
        )
    }
}
