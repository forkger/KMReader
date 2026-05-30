//
// PanelSequence.swift
//
//

import Foundation

enum PanelSequence: Equatable, Sendable {
    case empty
    case panels([PanelRect])

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    /// Total walk positions: N+2 (leading whole-page · N panels · trailing whole-page).
    /// Returns 0 for the empty sequence (panel mode cannot engage).
    var count: Int {
        switch self {
        case .empty:
            return 0
        case .panels(let rects):
            return rects.count + 2
        }
    }

    /// Panel rect for a cursor index, or nil for a whole-page position.
    /// Index 0 = leading whole-page; 1…N = panel[0…N-1]; N+1 = trailing whole-page.
    subscript(index: Int) -> PanelRect? {
        guard case .panels(let rects) = self else { return nil }
        guard index >= 0 && index < rects.count + 2 else { return nil }
        if index == 0 || index == rects.count + 1 { return nil }
        return rects[index - 1]
    }
}
