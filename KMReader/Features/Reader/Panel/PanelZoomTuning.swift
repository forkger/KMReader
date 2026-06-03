//
// PanelZoomTuning.swift
//
//

import Foundation

/// Single source of truth for the panel-walk zoom feel, shared by the iOS and macOS
/// cover-engine zoom surfaces. UIKit's built-in `zoom(to:animated:)` and AppKit's
/// implicit animator both run ~0.3s by default, which reads as an abrupt jump when
/// stepping panel to panel. Slow it down a touch here; this is a Phase D tuning knob.
enum PanelZoomTuning {
    /// Duration of an animated panel-to-panel zoom step, in seconds. User-tunable via the
    /// "Panel Mode" reader setting (`AppConfig.panelZoomDuration`, clamped 0.3...0.5). Read
    /// per step so a change applies immediately to the next zoom.
    static var stepDuration: TimeInterval { AppConfig.panelZoomDuration }
}
