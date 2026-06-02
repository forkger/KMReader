#if os(iOS) || os(tvOS)
  import AVFoundation
  import SwiftUI
  import UIKit

  final class NativePagedPageContentView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private var pageViews: [NativePageItem] = []

    private weak var viewModel: ReaderViewModel?
    private var currentItem: ReaderViewItem?
    private var currentPageData: [NativePageData] = []
    private var currentScreenSize: CGSize = .zero
    private var currentSplitWidePageMode: SplitWidePageMode = .auto
    private var renderConfig = ReaderRenderConfig(
      tapZoneMode: .defaultLayout,
      tapZoneInversionMode: .auto,
      showPageNumber: true,
      showPageShadow: true,
      readerBackground: .system,
      enableLiveText: false,
      enableImageContextMenu: false,
      supportsPageIsolationActions: false,
      doubleTapZoomScale: 3.0,
      doubleTapZoomMode: .fast
    )
    private var readingDirection: ReadingDirection = .ltr
    private var isPlaybackActive = false
    private var tracksGlobalZoomState = true
    private var isUpdatingZoomState = false

    override init(frame: CGRect) {
      super.init(frame: frame)
      setupUI()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
      super.layoutSubviews()
      updatePages()
    }

    func configure(
      viewModel: ReaderViewModel,
      item: ReaderViewItem,
      screenSize: CGSize,
      renderConfig: ReaderRenderConfig,
      readingDirection: ReadingDirection,
      splitWidePageMode: SplitWidePageMode,
      isPlaybackActive: Bool,
      tracksGlobalZoomState: Bool
    ) {
      let itemChanged = currentItem != item

      self.viewModel = viewModel
      self.currentItem = item
      self.currentScreenSize = screenSize
      self.currentSplitWidePageMode = splitWidePageMode
      self.renderConfig = renderConfig
      self.readingDirection = readingDirection
      self.isPlaybackActive = isPlaybackActive
      self.tracksGlobalZoomState = tracksGlobalZoomState
      self.currentPageData = viewModel.nativePageData(
        for: item,
        readingDirection: readingDirection,
        splitWidePageMode: splitWidePageMode,
        isPlaybackActive: isPlaybackActive
      )

      if itemChanged {
        resetZoomState()
      }

      scrollView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      backgroundColor = UIColor(renderConfig.readerBackground.color)
      contentStack.semanticContentAttribute =
        readingDirection == .rtl ? .forceRightToLeft : .forceLeftToRight

      updatePages()
    }

    func updatePlaybackActive(_ isPlaybackActive: Bool) {
      guard self.isPlaybackActive != isPlaybackActive else { return }
      self.isPlaybackActive = isPlaybackActive
      guard let viewModel, let currentItem else { return }

      currentPageData = viewModel.nativePageData(
        for: currentItem,
        readingDirection: readingDirection,
        splitWidePageMode: currentSplitWidePageMode,
        isPlaybackActive: isPlaybackActive
      )
      updatePages()
    }

    func resetContent(backgroundColor: UIColor? = nil) {
      viewModel = nil
      currentItem = nil
      currentPageData = []
      currentScreenSize = .zero
      isPlaybackActive = false
      tracksGlobalZoomState = true
      if let backgroundColor {
        self.backgroundColor = backgroundColor
        scrollView.backgroundColor = backgroundColor
      }
      pageViews.forEach { $0.prepareForDismantle() }
      resetZoomState()
    }

    private func setupUI() {
      backgroundColor = .clear

      scrollView.translatesAutoresizingMaskIntoConstraints = false
      scrollView.delegate = self
      scrollView.minimumZoomScale = 1.0
      scrollView.maximumZoomScale = 8.0
      scrollView.showsHorizontalScrollIndicator = false
      scrollView.showsVerticalScrollIndicator = false
      scrollView.contentInsetAdjustmentBehavior = .never
      scrollView.bouncesZoom = true
      scrollView.backgroundColor = UIColor(renderConfig.readerBackground.color)
      addSubview(scrollView)

      contentStack.axis = .horizontal
      contentStack.distribution = .fillEqually
      contentStack.alignment = .fill
      contentStack.spacing = 0
      contentStack.translatesAutoresizingMaskIntoConstraints = false
      scrollView.addSubview(contentStack)

      NSLayoutConstraint.activate([
        scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
        scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        scrollView.topAnchor.constraint(equalTo: topAnchor),
        scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
        contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
        contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
        contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
        contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        contentStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
      ])

      #if os(tvOS)
        scrollView.isScrollEnabled = false
        scrollView.panGestureRecognizer.isEnabled = false
      #else
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        scrollView.addGestureRecognizer(doubleTap)
      #endif
    }

    private func updatePages() {
      guard let viewModel else { return }
      let pages = currentPageData
      let canIsolatePageFromCurrentPresentation =
        renderConfig.supportsPageIsolationActions
        && pages.count == 2
        && Set(pages.map(\.pageID)).count == 2

      if pageViews.count != pages.count {
        pageViews.forEach { view in
          view.prepareForDismantle()
          view.removeFromSuperview()
        }
        pageViews = pages.map { _ in NativePageItem() }
        pageViews.forEach { contentStack.addArrangedSubview($0) }
      }

      let targetHeight = bounds.height > 0 ? bounds.height : currentScreenSize.height

      for (index, data) in pages.enumerated() {
        let image = viewModel.preloadedImage(for: data.pageID)
        pageViews[index].update(
          with: data,
          viewModel: viewModel,
          image: image,
          showPageNumber: renderConfig.showPageNumber,
          showPageShadow: renderConfig.showPageShadow,
          enableLiveText: renderConfig.enableLiveText,
          enableImageContextMenu: renderConfig.enableImageContextMenu,
          supportsPageIsolationActions: renderConfig.supportsPageIsolationActions,
          canIsolatePageFromCurrentPresentation: canIsolatePageFromCurrentPresentation,
          background: renderConfig.readerBackground,
          readingDirection: readingDirection,
          displayMode: .fit,
          targetHeight: targetHeight
        )
      }
    }

    private func resetZoomState() {
      isUpdatingZoomState = true
      scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
      scrollView.contentOffset = .zero
      isUpdatingZoomState = false

      guard tracksGlobalZoomState, let viewModel, viewModel.isZoomed else { return }
      viewModel.isZoomed = false
    }

    // Reset this slot's scroll view to minimum scale unconditionally, independent
    // of tracksGlobalZoomState or item identity. Lets the cover coordinator clear
    // a stale scale left on a slot that was zoomed while a page transition was in
    // flight. Uses isUpdatingZoomState so it does not re-fire scrollViewDidZoom.
    func forceResetZoom() {
      guard scrollView.zoomScale != scrollView.minimumZoomScale else { return }
      isUpdatingZoomState = true
      scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
      scrollView.contentOffset = .zero
      isUpdatingZoomState = false
    }

    // MARK: - Panel mode zoom (driven by PanelZoomController via the cover coordinator)

    /// Zoom to a normalized [0,1] page-space panel rect. The rect is mapped through the
    /// aspect-fit (letterboxed) image frame, not the raw scroll bounds, so the panel is
    /// framed correctly on letterboxed pages. Lets `scrollViewDidZoom` set `isZoomed`.
    func zoomToPanelRect(_ panel: PanelRect, animated: Bool) {
      let container = CGRect(origin: .zero, size: scrollView.bounds.size)
      guard container.width > 0, container.height > 0 else { return }
      let fitted = fittedImageRect(in: container)
      let target = CGRect(
        x: fitted.minX + panel.x * fitted.width,
        y: fitted.minY + panel.y * fitted.height,
        width: max(panel.width * fitted.width, 1),
        height: max(panel.height * fitted.height, 1)
      )
      scrollView.zoom(to: target, animated: animated)
    }

    /// Reset back to the whole, fitted page.
    func resetPanelZoomToFit(animated: Bool) {
      guard scrollView.zoomScale != scrollView.minimumZoomScale else { return }
      if animated {
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
      } else {
        forceResetZoom()
        if tracksGlobalZoomState, let viewModel, viewModel.isZoomed {
          viewModel.isZoomed = false
        }
      }
    }

    /// Convert a point in this view's coordinate space to normalized [0,1] image-space
    /// (through the aspect-fit frame). Points in the letterbox fall outside [0,1].
    func normalizedImagePoint(forContainerPoint point: CGPoint) -> CGPoint? {
      let container = CGRect(origin: .zero, size: scrollView.bounds.size)
      guard container.width > 0, container.height > 0 else { return nil }
      let fitted = fittedImageRect(in: container)
      guard fitted.width > 0, fitted.height > 0 else { return nil }
      return CGPoint(
        x: (point.x - fitted.minX) / fitted.width,
        y: (point.y - fitted.minY) / fitted.height
      )
    }

    private func fittedImageRect(in container: CGRect) -> CGRect {
      guard let imageSize = currentDisplayedImageSize(),
        imageSize.width > 0, imageSize.height > 0
      else {
        return container
      }
      return AVMakeRect(aspectRatio: imageSize, insideRect: container)
    }

    private func currentDisplayedImageSize() -> CGSize? {
      guard let viewModel, let data = currentPageData.first else { return nil }
      return viewModel.preloadedImage(for: data.pageID)?.size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
      contentStack
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
      guard tracksGlobalZoomState else { return }
      guard !isUpdatingZoomState else { return }
      guard let viewModel else { return }

      let zoomed = scrollView.zoomScale > (scrollView.minimumZoomScale + 0.01)
      if viewModel.isZoomed != zoomed {
        viewModel.isZoomed = zoomed
      }
    }

    #if os(iOS) || os(macOS)
      @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard renderConfig.doubleTapZoomMode != .disabled else { return }

        if scrollView.zoomScale > (scrollView.minimumZoomScale + 0.01) {
          scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
          return
        }

        let targetScale = min(
          CGFloat(renderConfig.doubleTapZoomScale),
          scrollView.maximumZoomScale
        )
        let center = gesture.location(in: contentStack)
        let width = scrollView.frame.size.width / targetScale
        let height = scrollView.frame.size.height / targetScale
        let rect = CGRect(
          x: center.x - width / 2,
          y: center.y - height / 2,
          width: width,
          height: height
        )
        scrollView.zoom(to: rect, animated: true)
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
      ) -> Bool {
        if let view = touch.view, view is UIControl {
          return false
        }
        return true
      }

      func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
      ) -> Bool {
        true
      }
    #endif
  }
#endif
