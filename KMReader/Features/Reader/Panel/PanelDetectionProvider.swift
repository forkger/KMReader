//
// PanelDetectionProvider.swift
//
//

import CoreGraphics

protocol PanelDetectionProvider: Sendable {
    var version: String { get }
    func detect(image: CGImage, direction: ReadingDirection) async -> PanelSequence
}
