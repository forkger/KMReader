//
// PanelModeController.swift
//
//

import CoreGraphics
import Foundation

/// Result of a `step`: either the controller handled it internally (zoomed within the
/// page) or the host must turn the page (the controller has recorded the direction so
/// the post-turn `updateCurrentPage` lands the cursor on the right whole-page bookend).
enum PanelStepOutcome: Equatable {
    case handled
    case turnPage(forward: Bool)
}

/// The brain of panel mode: owns the engaged state and a cursor over the current page's
/// `PanelSequence`, driving its `PanelZoomController`. It never calls back into the host;
/// the host reads `engaged`, calls `updateCurrentPage` / `engage` / `disengage` / `step`,
/// and performs page turns itself when `step` returns `.turnPage`.
///
/// Cursor is the N+2 array `[leading whole-page · panel[0…N-1] · trailing whole-page]`:
/// index 0 = leading whole-page, 1…N = panels, N+1 = trailing whole-page. The sequence is
/// already reading-ordered, so `step(forward:)` is direction-agnostic here.
@MainActor
@Observable
final class PanelModeController {
    /// Actively panel-walking — the host-facing `panelModeEngaged` signal that gates
    /// `.cover` pinning, the single-page invariant, and the Phase-D carve-outs.
    private(set) var engaged = false

    /// Owned here and exposed so the host can bind its `target` to the cover coordinator.
    let zoomController = PanelZoomController()

    private let orchestrator: PanelSequenceOrchestrator
    private var currentBookId: String?
    private var currentPage: BookPage?
    private var currentDirection: ReadingDirection = .ltr
    private var sequence: PanelSequence = .empty
    private var cursor = 0
    private var pendingTurnForward: Bool?

    init(provider: any PanelDetectionProvider = StubPanelProvider()) {
        self.orchestrator = PanelSequenceOrchestrator(provider: provider)
    }

    var currentPageHasPanels: Bool {
        if case .panels(let rects) = sequence { return !rects.isEmpty }
        return false
    }

    /// Called by the reader whenever the displayed page changes (armed or engaged).
    /// Eager-fetches the sequence; if a page turn is pending, lands the cursor on the
    /// whole-page bookend of the freshly turned-to page.
    func updateCurrentPage(bookId: String, page: BookPage, direction: ReadingDirection) async {
        currentBookId = bookId
        currentPage = page
        currentDirection = direction

        let resolved = await orchestrator.sequence(bookId: bookId, page: page, direction: direction)

        // Drop a late result if the page changed again while awaiting.
        guard currentBookId == bookId, currentPage?.number == page.number else { return }
        sequence = resolved

        guard engaged, let forward = pendingTurnForward else { return }
        pendingTurnForward = nil
        // Land on the whole-page bookend (fit; completeTransition already reset zoom).
        cursor = forward ? 0 : max(sequence.count - 1, 0)
        zoomController.resetToFit(animated: false)
    }

    /// Double-tap engage at a normalized [0,1] page-space point (gutter → panel 0).
    /// No-ops on a page with no panels; if the sequence is not ready yet, waits briefly.
    func engage(atNormalizedPoint point: CGPoint?) {
        if currentPageHasPanels {
            performEngage(at: point)
            return
        }
        guard let bookId = currentBookId, let page = currentPage else { return }
        let direction = currentDirection
        Task { [weak self] in
            guard let self else { return }
            let resolved = await self.orchestrator.sequence(
                bookId: bookId, page: page, direction: direction)
            guard self.currentBookId == bookId, self.currentPage?.number == page.number else { return }
            self.sequence = resolved
            guard self.currentPageHasPanels else { return }  // genuinely empty → stay armed
            self.performEngage(at: point)
        }
    }

    func disengage() {
        guard engaged else { return }
        engaged = false
        pendingTurnForward = nil
        cursor = 0
        zoomController.resetToFit(animated: true)
    }

    /// Toggle engage/disengage at a point (the double-tap gesture).
    func toggleEngagement(atNormalizedPoint point: CGPoint?) {
        if engaged {
            disengage()
        } else {
            engage(atNormalizedPoint: point)
        }
    }

    @discardableResult
    func step(forward: Bool) -> PanelStepOutcome {
        guard engaged else { return .handled }
        let lastIndex = sequence.count - 1
        if lastIndex < 1 {
            pendingTurnForward = forward
            return .turnPage(forward: forward)
        }
        let next = forward ? cursor + 1 : cursor - 1
        if next < 0 || next > lastIndex {
            pendingTurnForward = forward
            return .turnPage(forward: forward)
        }
        cursor = next
        zoomToCurrentCursor(animated: true)
        return .handled
    }

    // MARK: - Private

    private func performEngage(at point: CGPoint?) {
        cursor = point.flatMap(panelArrayIndex(at:)) ?? 1
        engaged = true
        pendingTurnForward = nil
        zoomToCurrentCursor(animated: true)
    }

    private func zoomToCurrentCursor(animated: Bool) {
        if let rect = sequence[cursor] {
            zoomController.zoomToRect(rect, animated: animated)
        } else {
            zoomController.resetToFit(animated: animated)
        }
    }

    /// N+2 array index (1…N) of the panel containing `point`, or nil for a gutter.
    private func panelArrayIndex(at point: CGPoint) -> Int? {
        guard case .panels(let rects) = sequence else { return nil }
        for (index, rect) in rects.enumerated() where
            point.x >= rect.x && point.x <= rect.x + rect.width
            && point.y >= rect.y && point.y <= rect.y + rect.height {
            return index + 1
        }
        return nil
    }
}
