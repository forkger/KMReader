//
// ReaderRenderConfig.swift
//
//

import Foundation

struct ReaderRenderConfig: Equatable {
  let tapZoneMode: TapZoneMode
  let tapZoneInversionMode: TapZoneInversionMode
  let showPageNumber: Bool
  let showPageShadow: Bool
  let readerBackground: ReaderBackground
  let enableLiveText: Bool
  let enableImageContextMenu: Bool
  let supportsPageIsolationActions: Bool
  let doubleTapZoomScale: Double
  let doubleTapZoomMode: DoubleTapZoomMode
  let panelMode: Bool

  init(
    tapZoneMode: TapZoneMode,
    tapZoneInversionMode: TapZoneInversionMode,
    showPageNumber: Bool,
    showPageShadow: Bool,
    readerBackground: ReaderBackground,
    enableLiveText: Bool,
    enableImageContextMenu: Bool,
    supportsPageIsolationActions: Bool,
    doubleTapZoomScale: Double,
    doubleTapZoomMode: DoubleTapZoomMode,
    panelMode: Bool = false
  ) {
    self.tapZoneMode = tapZoneMode
    self.tapZoneInversionMode = tapZoneInversionMode
    self.showPageNumber = showPageNumber
    self.showPageShadow = showPageShadow
    self.readerBackground = readerBackground
    self.enableLiveText = enableLiveText
    self.enableImageContextMenu = enableImageContextMenu
    self.supportsPageIsolationActions = supportsPageIsolationActions
    self.doubleTapZoomScale = doubleTapZoomScale
    self.doubleTapZoomMode = doubleTapZoomMode
    self.panelMode = panelMode
  }
}
