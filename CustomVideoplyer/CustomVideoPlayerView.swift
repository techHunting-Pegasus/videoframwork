//
//  CustomVideoPlayerView.swift
//  CustomVideoplyer
//
//  Created by Codex on 22/05/26.
//

import AVFoundation
import UIKit

public struct CustomVideoQualityOption: Equatable {
    public let id: String
    public let title: String
    public let peakBitRate: Double

    public init(id: String, title: String, peakBitRate: Double) {
        self.id = id
        self.title = title
        self.peakBitRate = peakBitRate
    }

    public static let auto = CustomVideoQualityOption(
        id: "auto",
        title: "Auto",
        peakBitRate: 0
    )
}

public enum CustomVideoPlayerControlButton: CaseIterable, Hashable {
    case backward
    case playPause
    case forward
    case cc
    case settings
    case expand
    case videoScale
    case liveStatus
}

public enum CustomVideoPlayerIconRole: CaseIterable, Hashable {
    case backward
    case play
    case pause
    case forward
    case cc
    case settings
    case expand
    case collapse
    case videoScaleAspect
    case videoScaleAspectFill
}

public final class CustomVideoPlayerView: UIView, UIGestureRecognizerDelegate {
    public override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    public var player: AVPlayer? {
        get { playerLayer.player }
        set { setPlayer(newValue) }
    }

    public var videoGravity: AVLayerVideoGravity {
        get { playerLayer.videoGravity }
        set {
            playerLayer.videoGravity = newValue
            updateVideoScaleButtonIcon()
        }
    }

    public var onExpandTapped: (() -> Void)?
    public var onStreamURLRefreshRequested: ((_ completion: @escaping (URL?) -> Void) -> Void)?

    // If empty, qualities are fetched dynamically from the current stream.
    // If non-empty, user-provided values override dynamic options.
    public var qualityOptions: [CustomVideoQualityOption] = [] {
        didSet {
            resolveSelectedQualityAndApply()
        }
    }

    public private(set) var selectedQualityID: String = CustomVideoQualityOption.auto.id
    public private(set) var selectedPlaybackSpeed: Float = 1.0

    private let controlsContainer = UIView()
    private let controlsStackView = UIStackView()
    private let secondaryStackView = UIStackView()
    private let landscapeCustomButtonsStackView = UIStackView()
    private let centerControlsStackView = UIStackView()
    private let titleLabel = UILabel()
    private let loadingStackView = UIStackView()
    private let loadingIndicator = UIActivityIndicatorView(style: .large)
    private let controlsGradientLayer = CAGradientLayer()

    private let backwardButton = UIButton(type: .system)
    private let playPauseButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let liveStatusButton = UIButton(type: .system)
    private let ccButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let expandButton = UIButton(type: .system)
    private let videoScaleButton = UIButton(type: .system)

    private let currentTimeLabel = UILabel()
    private let totalTimeLabel = UILabel()
    private let seekSlider = UISlider()

    private var isSeekingFromSlider = false

    private var timeObserver: Any?
    private var timeControlStatusObserver: NSKeyValueObservation?
    private var currentItemObserver: NSKeyValueObservation?
    private var currentItemStatusObserver: NSKeyValueObservation?
    private var currentItemDurationObserver: NSKeyValueObservation?
    private var currentItemBufferEmptyObserver: NSKeyValueObservation?
    private var currentItemLikelyToKeepUpObserver: NSKeyValueObservation?
    private var playbackStalledObserver: NSObjectProtocol?
    private var didPlayToEndObserver: NSObjectProtocol?
    private var streamQualityOptions: [CustomVideoQualityOption] = [.auto]
    private let playbackSpeedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    private var isApplyingPlaybackSpeed = false
    private var qualityFetchToken = UUID()
    private var customControlIcons: [CustomVideoPlayerIconRole: UIImage] = [:]
    private var customControlTintColors: [CustomVideoPlayerControlButton: UIColor] = [:]
    private var liveAtEdgeTitleColor: UIColor = .systemRed
    private var liveGoLiveTitleColor: UIColor = .white
    private var playerTitleText: String?
    private let defaultPlayerTitleTextColor: UIColor = .white
    private var playerTitleTextColor: UIColor = .white
    private let defaultPlayerTitleFont: UIFont = .systemFont(ofSize: 15, weight: .semibold)
    private var playerTitleFont: UIFont = .systemFont(ofSize: 15, weight: .semibold)
    private let defaultControlsGradientTopColor: UIColor = .clear
    private let defaultControlsGradientBottomColor: UIColor = UIColor.black.withAlphaComponent(0.88)
    private var controlsAutoHideWorkItem: DispatchWorkItem?
    private var isControlsVisible = true
    private let controlsAutoHideDelay: TimeInterval = 5
    private var verticalPanMode: VerticalPanMode = .none
    private var panStartBrightness: CGFloat = UIScreen.main.brightness
    private var panStartVolume: Float = 1
    private var isExpandedFullscreen = false
    private weak var fullscreenHostView: UIView?
    private var fullscreenConstraints: [NSLayoutConstraint] = []
    private weak var originalSuperviewForFullscreen: UIView?
    private var originalSuperviewIndexForFullscreen: Int = 0
    private var storedSuperviewConstraints: [NSLayoutConstraint] = []
    private var storedSelfSizingConstraints: [NSLayoutConstraint] = []
    private var previousNavigationBarHidden: Bool?
    private var currentVideoZoomScale: CGFloat = 1
    private var pinchStartZoomScale: CGFloat = 1
    private let minimumVideoZoomScale: CGFloat = 1
    private let maximumVideoZoomScale: CGFloat = 3
    private var sourceURL: URL?
    private var recoveryRetryWorkItem: DispatchWorkItem?
    private var recoveryAttempt = 0
    private let maximumRecoveryAttempts = 4
    private let recoveryBaseDelay: TimeInterval = 1.5

    private enum PlaybackMode {
        case vod
        case liveNoDVR
        case liveDVR
    }

    private var playbackMode: PlaybackMode = .vod
    private var liveWindowStartSeconds: Double = 0
    private var liveWindowEndSeconds: Double = 0
    private let liveEdgeToleranceSeconds: Double = 3
    private var landscapeCustomButtons: [UIButton] = []

    private enum VerticalPanMode {
        case none
        case brightness
        case volume
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        controlsGradientLayer.frame = controlsContainer.bounds
    }

    private func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func defaultControlImage(for role: CustomVideoPlayerIconRole) -> UIImage? {
        switch role {
        case .backward:
            return UIImage(systemName: "gobackward.10")
        case .play:
            return UIImage(systemName: "play.fill")
        case .pause:
            return UIImage(systemName: "pause.fill")
        case .forward:
            return UIImage(systemName: "goforward.10")
        case .cc:
            return UIImage(systemName: "captions.bubble")
        case .settings:
            return UIImage(systemName: "slider.horizontal.3")
        case .expand:
            return UIImage(systemName: "arrow.up.left.and.arrow.down.right")
        case .collapse:
            return UIImage(systemName: "arrow.down.right.and.arrow.up.left")
        case .videoScaleAspect:
            return UIImage(systemName: "aspectratio")
        case .videoScaleAspectFill:
            return UIImage(systemName: "aspectratio.fill")
        }
    }

    private func resolvedControlImage(for role: CustomVideoPlayerIconRole) -> UIImage? {
        customControlIcons[role] ?? defaultControlImage(for: role)
    }

    private func defaultTintColor(for button: CustomVideoPlayerControlButton) -> UIColor {
        switch button {
        case .backward, .playPause, .forward, .cc, .settings, .expand, .videoScale:
            return .white
        case .liveStatus:
            return .systemRed
        }
    }

    private func resolvedTintColor(for button: CustomVideoPlayerControlButton) -> UIColor {
        customControlTintColors[button] ?? defaultTintColor(for: button)
    }

    private func applyControlIcons() {
        backwardButton.setImage(resolvedControlImage(for: .backward), for: .normal)
        forwardButton.setImage(resolvedControlImage(for: .forward), for: .normal)
        ccButton.setImage(resolvedControlImage(for: .cc), for: .normal)
        settingsButton.setImage(resolvedControlImage(for: .settings), for: .normal)
        updatePlayPauseIcon()
        updateExpandButtonIcon()
        updateVideoScaleButtonIcon()
    }

    private func applyControlTintColors() {
        backwardButton.tintColor = resolvedTintColor(for: .backward)
        playPauseButton.tintColor = resolvedTintColor(for: .playPause)
        forwardButton.tintColor = resolvedTintColor(for: .forward)
        ccButton.tintColor = resolvedTintColor(for: .cc)
        settingsButton.tintColor = resolvedTintColor(for: .settings)
        expandButton.tintColor = resolvedTintColor(for: .expand)
        videoScaleButton.tintColor = resolvedTintColor(for: .videoScale)
        liveStatusButton.tintColor = resolvedTintColor(for: .liveStatus)
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            restoreNavigationBarIfNeeded()
        }
        updateExpandButtonIcon()
    }

    public init(
        player: AVPlayer? = nil,
        videoGravity: AVLayerVideoGravity = .resizeAspect
    ) {
        super.init(frame: .zero)
        setupUI()
        self.videoGravity = videoGravity
        setPlayer(player)
        updatePlayPauseIcon()
        refreshMenus()
        updateBufferingUI()
    }

    deinit {
        restoreNavigationBarIfNeeded()
        cancelRecoveryRetry()
        cancelAutoHideControls()
        removePlayerObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented. Use init(player:videoGravity:) instead.")
    }

    public func setVideoURL(_ url: URL) {
        sourceURL = url
        recoveryAttempt = 0
        cancelRecoveryRetry()

        let item = AVPlayerItem(url: url)

        if let existingPlayer = player {
            existingPlayer.replaceCurrentItem(with: item)
        } else {
            player = AVPlayer(playerItem: item)
        }

        refreshQualityOptionsFromStream()
        refreshPlaybackMode()
        updateBufferingUI()
    }

    public func setSelectedQuality(id: String) {
        guard effectiveQualityOptions().contains(where: { $0.id == id }) else { return }
        selectedQualityID = id
        applySelectedQuality()
        refreshMenus()
    }

    public func setSelectedPlaybackSpeed(_ speed: Float) {
        guard let matched = playbackSpeedOptions.first(where: { abs($0 - speed) < 0.001 }) else { return }
        selectedPlaybackSpeed = matched
        applySelectedPlaybackSpeed()
        refreshMenus()
    }

    public func play() {
        player?.play()
        applySelectedPlaybackSpeed()
        updatePlayPauseIcon()
        updateBufferingUI()
        scheduleAutoHideControlsIfNeeded()
    }

    public func pause() {
        player?.pause()
        updatePlayPauseIcon()
        setControlsVisible(true, animated: false)
    }

    public func stop() {
        player?.pause()
        player?.seek(to: .zero)
        updatePlayPauseIcon()
        setControlsVisible(true, animated: false)
    }

    public func setLandscapeCustomButtons(_ buttons: [UIButton]) {
        for button in landscapeCustomButtons {
            landscapeCustomButtonsStackView.removeArrangedSubview(button)
            button.removeFromSuperview()
        }

        landscapeCustomButtons = buttons

        for button in buttons {
            if button.superview != nil {
                button.removeFromSuperview()
            }
            button.translatesAutoresizingMaskIntoConstraints = false
            landscapeCustomButtonsStackView.addArrangedSubview(button)
        }

        updateLandscapeCustomButtonsVisibility()
    }

    public func setControlImage(_ image: UIImage?, for role: CustomVideoPlayerIconRole) {
        if let image {
            customControlIcons[role] = image
        } else {
            customControlIcons.removeValue(forKey: role)
        }
        applyControlIcons()
    }

    public func setControlTintColor(_ color: UIColor?, for button: CustomVideoPlayerControlButton) {
        if button == .liveStatus {
            if let color {
                liveAtEdgeTitleColor = color
                liveGoLiveTitleColor = color
            } else {
                liveAtEdgeTitleColor = .systemRed
                liveGoLiveTitleColor = .white
            }
            updateLiveStatusButton()
            return
        }

        if let color {
            customControlTintColors[button] = color
        } else {
            customControlTintColors.removeValue(forKey: button)
        }
        applyControlTintColors()
    }

    public func setLiveStatusTitleColors(atLiveEdge: UIColor, goLive: UIColor) {
        liveAtEdgeTitleColor = atLiveEdge
        liveGoLiveTitleColor = goLive
        updateLiveStatusButton()
    }

    public func setPlayerTitle(_ title: String?) {
        let normalized = title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (normalized?.isEmpty == false) ? normalized : nil

        playerTitleText = resolvedTitle
        titleLabel.text = resolvedTitle
        let shouldShow = isControlsVisible && !isBuffering() && resolvedTitle != nil
        setView(titleLabel, visible: shouldShow, animated: false)
    }

    public func setPlayerTitleTextColor(_ color: UIColor?) {
        playerTitleTextColor = color ?? defaultPlayerTitleTextColor
        titleLabel.textColor = playerTitleTextColor
    }

    public func setPlayerTitleFont(_ font: UIFont?) {
        playerTitleFont = font ?? defaultPlayerTitleFont
        titleLabel.font = playerTitleFont
    }

    public func setControlsGradientColors(top: UIColor?, bottom: UIColor?) {
        let resolvedTop = top ?? defaultControlsGradientTopColor
        let resolvedBottom = bottom ?? defaultControlsGradientBottomColor
        controlsGradientLayer.colors = [
            resolvedTop.cgColor,
            resolvedBottom.cgColor
        ]
    }

    private func setupUI() {
        backgroundColor = .black

        controlsContainer.translatesAutoresizingMaskIntoConstraints = false
        controlsContainer.backgroundColor = .clear
        setControlsGradientColors(top: nil, bottom: nil)
        controlsGradientLayer.locations = [0, 1]
        controlsGradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        controlsGradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        controlsContainer.layer.insertSublayer(controlsGradientLayer, at: 0)
        addSubview(controlsContainer)

        controlsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlsStackView.axis = .horizontal
        controlsStackView.alignment = .center
        controlsStackView.spacing = 8

        secondaryStackView.axis = .horizontal
        secondaryStackView.alignment = .center
        secondaryStackView.spacing = 6

        landscapeCustomButtonsStackView.axis = .horizontal
        landscapeCustomButtonsStackView.alignment = .center
        landscapeCustomButtonsStackView.spacing = 6
        landscapeCustomButtonsStackView.isHidden = true

        centerControlsStackView.translatesAutoresizingMaskIntoConstraints = false
        centerControlsStackView.axis = .horizontal
        centerControlsStackView.alignment = .center
        centerControlsStackView.spacing = 12

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = playerTitleFont
        titleLabel.textColor = playerTitleTextColor
        titleLabel.textAlignment = .left
        titleLabel.isUserInteractionEnabled = false
        titleLabel.isHidden = true
        titleLabel.alpha = 0
        addSubview(titleLabel)

        styleCenterSeekButton(backwardButton)
        styleCenterPlayPauseButton(playPauseButton)
        styleCenterSeekButton(forwardButton)

        centerControlsStackView.addArrangedSubview(backwardButton)
        centerControlsStackView.addArrangedSubview(playPauseButton)
        centerControlsStackView.addArrangedSubview(forwardButton)
        addSubview(centerControlsStackView)

        loadingStackView.translatesAutoresizingMaskIntoConstraints = false
        loadingStackView.axis = .vertical
        loadingStackView.alignment = .center
        loadingStackView.spacing = 8
        loadingStackView.isHidden = true

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.color = .white
        loadingIndicator.hidesWhenStopped = false

        loadingStackView.addArrangedSubview(loadingIndicator)
        addSubview(loadingStackView)

        styleControlButton(videoScaleButton)
        videoScaleButton.isHidden = true
        videoScaleButton.alpha = 0
        addSubview(videoScaleButton)

        styleLiveStatusButton(liveStatusButton)
        liveStatusButton.isHidden = true
        secondaryStackView.addArrangedSubview(liveStatusButton)

        [ccButton, settingsButton, expandButton].forEach { button in
            styleControlButton(button)
            secondaryStackView.addArrangedSubview(button)
        }

        currentTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        currentTimeLabel.textColor = .white
        currentTimeLabel.text = "00:00"
        currentTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        currentTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        totalTimeLabel.translatesAutoresizingMaskIntoConstraints = false
        totalTimeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        totalTimeLabel.textColor = .white
        totalTimeLabel.text = "00:00"
        totalTimeLabel.setContentHuggingPriority(.required, for: .horizontal)
        totalTimeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        seekSlider.translatesAutoresizingMaskIntoConstraints = false
        seekSlider.minimumValue = 0
        seekSlider.maximumValue = 1
        seekSlider.value = 0
        seekSlider.minimumTrackTintColor = .white
        seekSlider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.35)
        seekSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        seekSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        seekSlider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        controlsStackView.addArrangedSubview(currentTimeLabel)
        controlsStackView.addArrangedSubview(seekSlider)
        controlsStackView.addArrangedSubview(totalTimeLabel)
        controlsStackView.addArrangedSubview(landscapeCustomButtonsStackView)
        controlsStackView.addArrangedSubview(secondaryStackView)

        controlsContainer.addSubview(controlsStackView)

        let safeGuide = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            controlsContainer.leadingAnchor.constraint(equalTo: safeGuide.leadingAnchor),
            controlsContainer.trailingAnchor.constraint(equalTo: safeGuide.trailingAnchor),
            controlsContainer.bottomAnchor.constraint(equalTo: safeGuide.bottomAnchor),

            controlsStackView.leadingAnchor.constraint(equalTo: controlsContainer.leadingAnchor, constant: 10),
            controlsStackView.trailingAnchor.constraint(equalTo: controlsContainer.trailingAnchor, constant: -10),
            controlsStackView.topAnchor.constraint(equalTo: controlsContainer.topAnchor, constant: 8),
            controlsStackView.bottomAnchor.constraint(equalTo: controlsContainer.bottomAnchor, constant: -8),
            controlsStackView.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),

            centerControlsStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerControlsStackView.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: safeGuide.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: safeGuide.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeGuide.trailingAnchor, constant: -12),

            loadingStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            loadingStackView.centerYAnchor.constraint(equalTo: centerYAnchor),

            videoScaleButton.topAnchor.constraint(equalTo: safeGuide.topAnchor, constant: 12),
            videoScaleButton.trailingAnchor.constraint(equalTo: safeGuide.trailingAnchor, constant: -12)
        ])

        applyControlIcons()
        applyControlTintColors()

        backwardButton.addTarget(self, action: #selector(didTapBackward), for: .touchUpInside)
        playPauseButton.addTarget(self, action: #selector(didTapPlayPause), for: .touchUpInside)
        forwardButton.addTarget(self, action: #selector(didTapForward), for: .touchUpInside)
        liveStatusButton.addTarget(self, action: #selector(didTapLiveStatus), for: .touchUpInside)
        expandButton.addTarget(self, action: #selector(didTapExpand), for: .touchUpInside)
        videoScaleButton.addTarget(self, action: #selector(didTapVideoScale), for: .touchUpInside)

        ccButton.showsMenuAsPrimaryAction = true
        settingsButton.showsMenuAsPrimaryAction = true
        updateExpandButtonIcon()
        updateVideoScaleButtonIcon()
        refreshPlaybackMode()
        updateLiveControlsUI()
        updateLandscapeCustomButtonsVisibility()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapPlayerSurface))
        tapGesture.delegate = self
        tapGesture.cancelsTouchesInView = false
        addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(didPanPlayerSurface(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = false
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(didPinchPlayerSurface(_:)))
        pinchGesture.delegate = self
        pinchGesture.cancelsTouchesInView = false
        addGestureRecognizer(pinchGesture)

        tapGesture.require(toFail: panGesture)
    }

    private func styleControlButton(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = .clear
        button.layer.cornerRadius = 0
        button.clipsToBounds = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func styleLiveStatusButton(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("LIVE", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
        button.setTitleColor(liveAtEdgeTitleColor, for: .normal)
        button.setTitleColor(liveAtEdgeTitleColor, for: .disabled)
        button.backgroundColor = .clear
        button.contentEdgeInsets = .zero
    }

    private func styleCenterPlayPauseButton(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = .clear
        button.layer.cornerRadius = 0
        button.clipsToBounds = false
        button.widthAnchor.constraint(equalToConstant: 56).isActive = true
        button.heightAnchor.constraint(equalToConstant: 56).isActive = true
    }

    private func styleCenterSeekButton(_ button: UIButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.backgroundColor = .clear
        button.layer.cornerRadius = 0
        button.clipsToBounds = false
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    }

    private func setPlayer(_ newPlayer: AVPlayer?) {
        if playerLayer.player === newPlayer {
            return
        }

        removePlayerObservers()
        playerLayer.player = newPlayer
        if let assetURL = (newPlayer?.currentItem?.asset as? AVURLAsset)?.url {
            sourceURL = assetURL
        }
        installPlayerObservers()
        refreshDurationUI()
        refreshMenus()
        updatePlayPauseIcon()
        handlePlaybackStateChange()
    }

    private func installPlayerObservers() {
        guard let player else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] _ in
            self?.syncTimeUIFromPlayer()
        }

        timeControlStatusObserver = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            self?.runOnMain { [weak self] in
                self?.updatePlayPauseIcon()
                self?.handlePlaybackStateChange()
            }
        }

        currentItemObserver = player.observe(
            \.currentItem,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            self?.runOnMain { [weak self] in
                self?.bindCurrentItemObservers()
                self?.refreshQualityOptionsFromStream()
                self?.refreshDurationUI()
                self?.refreshMenus()
                self?.updateBufferingUI()
            }
        }

        bindCurrentItemObservers()
    }

    private func bindCurrentItemObservers() {
        currentItemStatusObserver = nil
        currentItemDurationObserver = nil
        currentItemBufferEmptyObserver = nil
        currentItemLikelyToKeepUpObserver = nil

        if let observer = playbackStalledObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackStalledObserver = nil
        }

        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }

        guard let item = player?.currentItem else {
            playbackMode = .vod
            updateLiveControlsUI()
            updateBufferingUI()
            return
        }

        if let assetURL = (item.asset as? AVURLAsset)?.url {
            sourceURL = assetURL
        }

        currentItemStatusObserver = item.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            self?.runOnMain { [weak self] in
                self?.refreshDurationUI()
                self?.refreshMenus()
                self?.updateBufferingUI()
                if item.status == .failed {
                    self?.scheduleRecoveryRetry(reason: "item_failed")
                }
            }
        }

        currentItemDurationObserver = item.observe(
            \.duration,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            self?.runOnMain { [weak self] in
                self?.refreshDurationUI()
                self?.updateBufferingUI()
            }
        }

        currentItemBufferEmptyObserver = item.observe(
            \.isPlaybackBufferEmpty,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            self?.runOnMain { [weak self] in
                self?.updateBufferingUI()
            }
        }

        currentItemLikelyToKeepUpObserver = item.observe(
            \.isPlaybackLikelyToKeepUp,
            options: [.initial, .new]
        ) { [weak self] _, _ in
            self?.runOnMain { [weak self] in
                self?.updateBufferingUI()
            }
        }

        playbackStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRecoveryRetry(reason: "playback_stalled")
        }

        didPlayToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.updatePlayPauseIcon()
            self?.syncTimeUIFromPlayer(force: true)
            self?.setControlsVisible(true, animated: false)
        }
    }

    private func removePlayerObservers() {
        cancelAutoHideControls()

        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        timeControlStatusObserver = nil
        currentItemObserver = nil
        currentItemStatusObserver = nil
        currentItemDurationObserver = nil
        currentItemBufferEmptyObserver = nil
        currentItemLikelyToKeepUpObserver = nil

        if let observer = didPlayToEndObserver {
            NotificationCenter.default.removeObserver(observer)
            didPlayToEndObserver = nil
        }

        if let observer = playbackStalledObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackStalledObserver = nil
        }

        cancelRecoveryRetry()
    }

    private func effectiveQualityOptions() -> [CustomVideoQualityOption] {
        let manual = qualityOptions
        if !manual.isEmpty {
            return normalizeQualityOptions(manual)
        }
        return streamQualityOptions
    }

    private func normalizeQualityOptions(_ options: [CustomVideoQualityOption]) -> [CustomVideoQualityOption] {
        if options.isEmpty {
            return [.auto]
        }

        var seen = Set<String>()
        var unique: [CustomVideoQualityOption] = []
        for option in options {
            if seen.insert(option.id).inserted {
                unique.append(option)
            }
        }
        return unique
    }

    private func resolveSelectedQualityAndApply() {
        let options = effectiveQualityOptions()
        if !options.contains(where: { $0.id == selectedQualityID }) {
            selectedQualityID = options.first?.id ?? CustomVideoQualityOption.auto.id
        }
        applySelectedQuality()
        refreshMenus()
    }

    private func refreshQualityOptionsFromStream() {
        let token = UUID()
        qualityFetchToken = token
        streamQualityOptions = [.auto]
        resolveSelectedQualityAndApply()

        guard
            qualityOptions.isEmpty,
            let item = player?.currentItem,
            let urlAsset = item.asset as? AVURLAsset
        else {
            return
        }

        let url = urlAsset.url
        guard isLikelyHLSURL(url) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self else { return }
            let parsed = self.parseQualityOptionsFromHLSManifest(data, sourceURL: url)

            DispatchQueue.main.async {
                guard self.qualityFetchToken == token else { return }
                self.streamQualityOptions = parsed.isEmpty ? [.auto] : parsed
                self.resolveSelectedQualityAndApply()
            }
        }.resume()
    }

    private func isLikelyHLSURL(_ url: URL) -> Bool {
        let lowercased = url.absoluteString.lowercased()
        return lowercased.contains(".m3u8")
    }

    private func parseQualityOptionsFromHLSManifest(_ data: Data?, sourceURL: URL?) -> [CustomVideoQualityOption] {
        guard
            let data,
            let manifest = String(data: data, encoding: .utf8)
        else {
            return inferSingleVariantQualityOption(manifest: nil, sourceURL: sourceURL).map { [.auto, $0] } ?? []
        }

        var qualities: [CustomVideoQualityOption] = []
        let lines = manifest.components(separatedBy: .newlines)

        for line in lines {
            guard line.hasPrefix("#EXT-X-STREAM-INF:") else { continue }
            let attributesString = String(line.dropFirst("#EXT-X-STREAM-INF:".count))
            let attributes = parseManifestAttributes(attributesString)

            guard
                let bandwidthString = attributes["AVERAGE-BANDWIDTH"] ?? attributes["BANDWIDTH"],
                let bandwidth = Double(bandwidthString)
            else {
                continue
            }

            let title: String
            if let resolution = attributes["RESOLUTION"] {
                let height = resolution.split(separator: "x").last.flatMap { Int($0) }
                if let height {
                    title = "\(height)p"
                } else {
                    title = formatBitRateTitle(bandwidth)
                }
            } else {
                title = formatBitRateTitle(bandwidth)
            }

            let id = "bitrate_\(Int(bandwidth))"
            qualities.append(
                CustomVideoQualityOption(
                    id: id,
                    title: title,
                    peakBitRate: bandwidth
                )
            )
        }

        if !qualities.isEmpty {
            qualities.sort { $0.peakBitRate < $1.peakBitRate }
            qualities = normalizeQualityOptions(qualities)
            return [CustomVideoQualityOption.auto] + qualities
        }

        if let fallback = inferSingleVariantQualityOption(manifest: manifest, sourceURL: sourceURL) {
            return [.auto, fallback]
        }

        return []
    }

    private func inferSingleVariantQualityOption(manifest: String?, sourceURL: URL?) -> CustomVideoQualityOption? {
        if let manifest, let bitRate = extractBitRate(from: manifest), bitRate > 0 {
            let id = "bitrate_\(Int(bitRate))"
            return CustomVideoQualityOption(id: id, title: formatBitRateTitle(bitRate), peakBitRate: bitRate)
        }

        if let sourceURL, let bitRate = extractBitRate(from: sourceURL.absoluteString), bitRate > 0 {
            let id = "bitrate_\(Int(bitRate))"
            return CustomVideoQualityOption(id: id, title: formatBitRateTitle(bitRate), peakBitRate: bitRate)
        }

        return nil
    }

    private func extractBitRate(from text: String) -> Double? {
        let patterns = [
            #"video=(\d{4,})"#,
            #"bitrate(?:=|_)(\d{4,})"#,
            #"bandwidth(?:=|_)(\d{4,})"#,
            #"(\d{6,})k"# // defensive fallback for unconventional naming.
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1 else {
                continue
            }
            let numberRange = match.range(at: 1)
            guard numberRange.location != NSNotFound else { continue }
            let value = nsText.substring(with: numberRange)
            guard let parsed = Double(value) else { continue }

            if pattern.contains(#"(\d{6,})k"#) {
                return parsed * 1_000
            }
            return parsed
        }

        return nil
    }

    private func parseManifestAttributes(_ attributesString: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var parts: [String] = []
        var current = ""
        var insideQuotes = false

        for character in attributesString {
            if character == "\"" {
                insideQuotes.toggle()
            }

            if character == "," && !insideQuotes {
                parts.append(current)
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            attributes[key] = value
        }

        return attributes
    }

    private func formatBitRateTitle(_ bitRate: Double) -> String {
        if bitRate >= 1_000_000 {
            return String(format: "%.1f Mbps", bitRate / 1_000_000)
        }
        return String(format: "%.0f Kbps", bitRate / 1_000)
    }

    private func currentDurationSeconds() -> Double {
        guard let seconds = player?.currentItem?.duration.seconds else { return 0 }
        if !seconds.isFinite || seconds.isNaN || seconds < 0 {
            return 0
        }
        return seconds
    }

    private func currentPlaybackSeconds() -> Double {
        guard let seconds = player?.currentTime().seconds else { return 0 }
        if !seconds.isFinite || seconds.isNaN || seconds < 0 {
            return 0
        }
        return seconds
    }

    private func latestSeekableRange() -> CMTimeRange? {
        guard let item = player?.currentItem else { return nil }
        let ranges = item.seekableTimeRanges.compactMap { $0.timeRangeValue }
        return ranges.max {
            CMTimeRangeGetEnd($0).seconds < CMTimeRangeGetEnd($1).seconds
        }
    }

    private func refreshPlaybackMode() {
        let previousMode = playbackMode

        guard let item = player?.currentItem else {
            playbackMode = .vod
            liveWindowStartSeconds = 0
            liveWindowEndSeconds = 0
            if previousMode != playbackMode { updateLiveControlsUI() }
            return
        }

        let duration = item.duration.seconds
        let isFiniteDuration = duration.isFinite && !duration.isNaN && duration > 0 && !item.duration.isIndefinite

        if isFiniteDuration {
            playbackMode = .vod
            liveWindowStartSeconds = 0
            liveWindowEndSeconds = 0
        } else if let range = latestSeekableRange() {
            let start = max(0, range.start.seconds)
            let end = max(start, CMTimeRangeGetEnd(range).seconds)
            liveWindowStartSeconds = start
            liveWindowEndSeconds = end
            playbackMode = (end - start) > 2 ? .liveDVR : .liveNoDVR
        } else {
            let current = currentPlaybackSeconds()
            liveWindowStartSeconds = current
            liveWindowEndSeconds = current
            playbackMode = .liveNoDVR
        }

        if previousMode != playbackMode {
            updateLiveControlsUI()
        }
    }

    private func liveWindowDuration() -> Double {
        max(0, liveWindowEndSeconds - liveWindowStartSeconds)
    }

    private func isAtLiveEdge() -> Bool {
        guard playbackMode == .liveDVR else { return true }
        let behindLive = max(0, liveWindowEndSeconds - currentPlaybackSeconds())
        return behindLive <= liveEdgeToleranceSeconds
    }

    private func updateLiveControlsUI() {
        switch playbackMode {
        case .vod:
            liveStatusButton.isHidden = true
            seekSlider.isHidden = false
            totalTimeLabel.isHidden = false
            backwardButton.isHidden = false
            forwardButton.isHidden = false
            seekSlider.isEnabled = true
            backwardButton.isEnabled = true
            forwardButton.isEnabled = true
        case .liveNoDVR:
            liveStatusButton.isHidden = false
            seekSlider.isHidden = true
            totalTimeLabel.isHidden = true
            backwardButton.isHidden = true
            forwardButton.isHidden = true
            seekSlider.isEnabled = false
            backwardButton.isEnabled = false
            forwardButton.isEnabled = false
        case .liveDVR:
            liveStatusButton.isHidden = false
            seekSlider.isHidden = false
            totalTimeLabel.isHidden = false
            backwardButton.isHidden = false
            forwardButton.isHidden = false
            seekSlider.isEnabled = true
            backwardButton.isEnabled = true
            forwardButton.isEnabled = true
        }

        updateLiveStatusButton()
        updateLandscapeCustomButtonsVisibility()
    }

    private func updateLandscapeCustomButtonsVisibility() {
        let shouldShow = isExpandedFullscreen && playbackMode == .vod && !landscapeCustomButtons.isEmpty
        landscapeCustomButtonsStackView.isHidden = !shouldShow
        landscapeCustomButtonsStackView.alpha = shouldShow ? 1 : 0
        landscapeCustomButtonsStackView.isUserInteractionEnabled = shouldShow
    }

    private func updateLiveStatusButton() {
        switch playbackMode {
        case .vod:
            liveStatusButton.isHidden = true
            liveStatusButton.isEnabled = false
            liveStatusButton.setTitle(nil, for: .normal)
        case .liveNoDVR:
            liveStatusButton.isHidden = false
            liveStatusButton.isEnabled = false
            liveStatusButton.setTitle("LIVE", for: .normal)
            liveStatusButton.setTitleColor(liveAtEdgeTitleColor, for: .normal)
            liveStatusButton.setTitleColor(liveAtEdgeTitleColor, for: .disabled)
            liveStatusButton.alpha = 1
        case .liveDVR:
            liveStatusButton.isHidden = false
            let atLiveEdge = isAtLiveEdge()
            liveStatusButton.isEnabled = !atLiveEdge
            liveStatusButton.setTitle(atLiveEdge ? "LIVE" : "GO LIVE", for: .normal)
            let color = atLiveEdge ? liveAtEdgeTitleColor : liveGoLiveTitleColor
            liveStatusButton.setTitleColor(color, for: .normal)
            liveStatusButton.setTitleColor(color, for: .disabled)
            liveStatusButton.alpha = 1
        }
    }

    private func formatLiveBehindLabel(_ behindSeconds: Double) -> String {
        if behindSeconds <= liveEdgeToleranceSeconds {
            return "LIVE"
        }
        return "-\(formatTime(behindSeconds))"
    }

    private func refreshDurationUI() {
        refreshPlaybackMode()

        switch playbackMode {
        case .vod:
            let duration = currentDurationSeconds()
            seekSlider.maximumValue = Float(max(duration, 1))
            totalTimeLabel.text = formatTime(duration)
        case .liveNoDVR:
            seekSlider.maximumValue = 1
            totalTimeLabel.text = ""
        case .liveDVR:
            seekSlider.maximumValue = Float(max(liveWindowDuration(), 1))
            totalTimeLabel.text = "LIVE"
        }

        updateLiveControlsUI()
        syncTimeUIFromPlayer(force: true)
    }

    private func syncTimeUIFromPlayer(force: Bool = false) {
        refreshPlaybackMode()
        let current = currentPlaybackSeconds()

        switch playbackMode {
        case .vod:
            currentTimeLabel.text = formatTime(current)
            if force || !isSeekingFromSlider {
                let clamped = min(current, currentDurationSeconds())
                seekSlider.value = Float(max(0, clamped))
            }
        case .liveNoDVR:
            currentTimeLabel.text = "LIVE"
            totalTimeLabel.text = ""
            if force || !isSeekingFromSlider {
                seekSlider.value = 1
            }
        case .liveDVR:
            let start = liveWindowStartSeconds
            let end = max(liveWindowEndSeconds, start)
            let clampedCurrent = min(max(current, start), end)
            let behindLive = max(0, end - clampedCurrent)
            currentTimeLabel.text = formatLiveBehindLabel(behindLive)
            totalTimeLabel.text = "LIVE"

            if force || !isSeekingFromSlider {
                let relative = max(0, clampedCurrent - start)
                seekSlider.maximumValue = Float(max(end - start, 1))
                seekSlider.value = Float(relative)
            }
        }

        updateLiveStatusButton()
    }

    private func updatePlayPauseIcon() {
        let role: CustomVideoPlayerIconRole = (player?.timeControlStatus == .playing) ? .pause : .play
        playPauseButton.setImage(resolvedControlImage(for: role), for: .normal)
    }

    private func handlePlaybackStateChange() {
        let status = player?.timeControlStatus

        if status == .playing {
            recoveryAttempt = 0
            cancelRecoveryRetry()
            scheduleAutoHideControlsIfNeeded()
        } else if status == .paused {
            isControlsVisible = true
            cancelAutoHideControls()
        } else {
            cancelAutoHideControls()
        }

        updateBufferingUI()
    }

    private func isBuffering() -> Bool {
        guard
            let player,
            let item = player.currentItem
        else {
            return false
        }

        if item.status == .failed {
            return false
        }

        if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            return true
        }

        return item.isPlaybackBufferEmpty && !item.isPlaybackLikelyToKeepUp && player.rate > 0
    }

    private func updateBufferingUI(animated: Bool = false) {
        let buffering = isBuffering()
        let shouldShowControls = !buffering && isControlsVisible

        setControlsContentVisible(shouldShowControls, animated: animated)
        loadingStackView.isHidden = !buffering

        if buffering {
            loadingIndicator.startAnimating()
            cancelAutoHideControls()
        } else {
            loadingIndicator.stopAnimating()
            scheduleAutoHideControlsIfNeeded()
        }
    }

    private func scheduleRecoveryRetry(reason _: String) {
        guard recoveryAttempt < maximumRecoveryAttempts else { return }
        guard sourceURL != nil || onStreamURLRefreshRequested != nil else { return }

        recoveryAttempt += 1
        let delay = recoveryBaseDelay * pow(2, Double(recoveryAttempt - 1))

        cancelRecoveryRetry()
        let workItem = DispatchWorkItem { [weak self] in
            self?.performRecoveryRetry()
        }
        recoveryRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func performRecoveryRetry() {
        if let refreshHandler = onStreamURLRefreshRequested {
            refreshHandler { [weak self] refreshedURL in
                DispatchQueue.main.async {
                    let fallbackURL = self?.sourceURL
                    self?.reloadPlayerSource(with: refreshedURL ?? fallbackURL)
                }
            }
            return
        }

        reloadPlayerSource(with: sourceURL)
    }

    private func reloadPlayerSource(with url: URL?) {
        guard let url else { return }
        setVideoURL(url)
        play()
    }

    private func cancelRecoveryRetry() {
        recoveryRetryWorkItem?.cancel()
        recoveryRetryWorkItem = nil
    }

    private func setControlsVisible(_ visible: Bool, animated: Bool) {
        isControlsVisible = visible
        updateBufferingUI(animated: animated)
    }

    private func setControlsContentVisible(_ visible: Bool, animated: Bool) {
        setView(controlsContainer, visible: visible, animated: animated)
        setView(centerControlsStackView, visible: visible, animated: animated)
        setView(titleLabel, visible: visible && playerTitleText != nil, animated: animated)
        setView(videoScaleButton, visible: visible && isExpandedFullscreen, animated: animated)
    }

    private func setView(_ view: UIView, visible: Bool, animated: Bool) {
        if visible {
            guard view.isHidden || view.alpha < 1 else { return }
            view.isHidden = false
            if animated {
                UIView.animate(withDuration: 0.2) {
                    view.alpha = 1
                }
            } else {
                view.alpha = 1
            }
            return
        }

        guard !view.isHidden || view.alpha > 0 else { return }
        if animated {
            UIView.animate(withDuration: 0.2, animations: {
                view.alpha = 0
            }) { _ in
                view.isHidden = true
            }
        } else {
            view.alpha = 0
            view.isHidden = true
        }
    }

    private func scheduleAutoHideControlsIfNeeded() {
        cancelAutoHideControls()

        guard
            isControlsVisible,
            player?.timeControlStatus == .playing,
            !isBuffering()
        else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard
                let self,
                self.player?.timeControlStatus == .playing,
                !self.isBuffering()
            else {
                return
            }
            self.setControlsVisible(false, animated: true)
        }

        controlsAutoHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + controlsAutoHideDelay,
            execute: workItem
        )
    }

    private func cancelAutoHideControls() {
        controlsAutoHideWorkItem?.cancel()
        controlsAutoHideWorkItem = nil
    }

    @objc private func didTapPlayerSurface() {
        guard !isBuffering() else { return }
        setControlsVisible(!isControlsVisible, animated: true)
    }

    @objc private func didPanPlayerSurface(_ gesture: UIPanGestureRecognizer) {
        guard !isBuffering() else { return }

        switch gesture.state {
        case .began:
            let startLocation = gesture.location(in: self)
            verticalPanMode = startLocation.x < bounds.midX ? .brightness : .volume
            panStartBrightness = UIScreen.main.brightness
            panStartVolume = player?.volume ?? 1
        case .changed:
            let verticalDistance = max(bounds.height, 1)
            let delta = Float(-gesture.translation(in: self).y / verticalDistance)

            switch verticalPanMode {
            case .brightness:
                let updatedBrightness = clamp01(panStartBrightness + CGFloat(delta))
                UIScreen.main.brightness = updatedBrightness
            case .volume:
                let updatedVolume = clamp01(panStartVolume + delta)
                player?.volume = updatedVolume
            case .none:
                break
            }
        case .ended, .cancelled, .failed:
            verticalPanMode = .none
        default:
            break
        }
    }

    private func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    @objc private func didPinchPlayerSurface(_ gesture: UIPinchGestureRecognizer) {
        guard !isBuffering(), isExpandedFullscreen else { return }

        switch gesture.state {
        case .began:
            pinchStartZoomScale = currentVideoZoomScale
        case .changed:
            let targetScale = pinchStartZoomScale * gesture.scale
            applyVideoZoomScale(targetScale)
        case .ended, .cancelled, .failed:
            if currentVideoZoomScale < (minimumVideoZoomScale + 0.01) {
                applyVideoZoomScale(minimumVideoZoomScale, animated: true)
            }
        default:
            break
        }
    }

    private func applyVideoZoomScale(_ scale: CGFloat, animated: Bool = false) {
        let clampedScale = min(max(scale, minimumVideoZoomScale), maximumVideoZoomScale)
        currentVideoZoomScale = clampedScale

        let transform = CGAffineTransform(scaleX: clampedScale, y: clampedScale)
        if animated {
            UIView.animate(withDuration: 0.2) { [weak self] in
                self?.playerLayer.setAffineTransform(transform)
            }
        } else {
            playerLayer.setAffineTransform(transform)
        }
    }

    private func isTouchInsideControl(_ view: UIView?) -> Bool {
        var current = view
        while let controlView = current {
            if controlView is UIControl {
                return true
            }
            current = controlView.superview
        }
        return false
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !isTouchInsideControl(touch.view)
    }

    @objc private func didTapPlayPause() {
        guard let player else { return }
        setControlsVisible(true, animated: false)
        if player.timeControlStatus == .playing {
            pause()
        } else {
            play()
        }
    }

    @objc private func didTapBackward() {
        setControlsVisible(true, animated: false)
        seekBy(seconds: -10)
        scheduleAutoHideControlsIfNeeded()
    }

    @objc private func didTapForward() {
        setControlsVisible(true, animated: false)
        seekBy(seconds: 10)
        scheduleAutoHideControlsIfNeeded()
    }

    private func seekBy(seconds: Double) {
        guard let player else { return }
        refreshPlaybackMode()

        if playbackMode == .liveNoDVR {
            return
        }

        if playbackMode == .liveDVR {
            let start = liveWindowStartSeconds
            let end = max(liveWindowEndSeconds, start)
            let current = currentPlaybackSeconds()
            let target = min(max(start, current + seconds), end)

            player.seek(
                to: CMTime(seconds: target, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            return
        }

        let current = currentPlaybackSeconds()
        let duration = currentDurationSeconds()
        var target = current + seconds

        if duration > 0 {
            target = min(max(0, target), duration)
        } else {
            target = max(0, target)
        }

        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    @objc private func sliderTouchDown() {
        if playbackMode == .liveNoDVR { return }
        isSeekingFromSlider = true
        setControlsVisible(true, animated: false)
        cancelAutoHideControls()
    }

    @objc private func sliderValueChanged() {
        if playbackMode == .liveDVR {
            let target = liveWindowStartSeconds + Double(seekSlider.value)
            let behindLive = max(0, liveWindowEndSeconds - target)
            currentTimeLabel.text = formatLiveBehindLabel(behindLive)
        } else {
            currentTimeLabel.text = formatTime(Double(seekSlider.value))
        }
    }

    @objc private func sliderTouchUp() {
        guard let player else { return }

        if playbackMode == .liveNoDVR {
            isSeekingFromSlider = false
            return
        }

        let seconds: Double
        if playbackMode == .liveDVR {
            seconds = liveWindowStartSeconds + Double(seekSlider.value)
        } else {
            seconds = Double(seekSlider.value)
        }

        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.isSeekingFromSlider = false
            self?.scheduleAutoHideControlsIfNeeded()
        }
    }

    @objc private func didTapExpand() {
        toggleLandscapeMode()
        onExpandTapped?()
    }

    @objc private func didTapLiveStatus() {
        guard playbackMode == .liveDVR else { return }
        seekToLiveEdge()
    }

    private func seekToLiveEdge() {
        guard playbackMode == .liveDVR else { return }
        let target = max(liveWindowStartSeconds, liveWindowEndSeconds - 0.5)
        player?.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
        ) { [weak self] _ in
            self?.syncTimeUIFromPlayer(force: true)
            self?.scheduleAutoHideControlsIfNeeded()
        }
    }

    @objc private func didTapVideoScale() {
        let nextGravity: AVLayerVideoGravity = (videoGravity == .resizeAspectFill) ? .resizeAspect : .resizeAspectFill
        videoGravity = nextGravity
        setControlsVisible(true, animated: false)
        scheduleAutoHideControlsIfNeeded()
    }

    private func toggleLandscapeMode() {
        if isExpandedFullscreen {
            exitFullscreenLandscape()
        } else {
            enterFullscreenLandscape()
        }
        updateExpandButtonIcon()
    }

    private func enterFullscreenLandscape() {
        guard let currentSuperview = superview else {
            isExpandedFullscreen = true
            applyVideoZoomScale(minimumVideoZoomScale)
            requestInterfaceOrientation(.landscapeRight)
            return
        }

        originalSuperviewForFullscreen = currentSuperview
        originalSuperviewIndexForFullscreen = currentSuperview.subviews.firstIndex(of: self) ?? currentSuperview.subviews.count

        storedSuperviewConstraints = constraintsForFullscreenExpansion(in: currentSuperview)
        storedSelfSizingConstraints = selfSizingConstraintsForFullscreen()
        NSLayoutConstraint.deactivate(storedSuperviewConstraints + storedSelfSizingConstraints)

        let hostView = fullscreenPresentationHostView(fallback: currentSuperview)
        fullscreenHostView = hostView

        if hostView !== currentSuperview {
            removeFromSuperview()
            hostView.addSubview(self)
        }

        translatesAutoresizingMaskIntoConstraints = false
        fullscreenConstraints = [
            leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            topAnchor.constraint(equalTo: hostView.topAnchor),
            bottomAnchor.constraint(equalTo: hostView.bottomAnchor)
        ]
        NSLayoutConstraint.activate(fullscreenConstraints)
        hostView.bringSubviewToFront(self)
        hostView.layoutIfNeeded()

        if let navigationController = nearestViewController()?.navigationController {
            previousNavigationBarHidden = navigationController.isNavigationBarHidden
            navigationController.setNavigationBarHidden(true, animated: false)
            navigationController.view.layoutIfNeeded()
        }

        isExpandedFullscreen = true
        applyVideoZoomScale(minimumVideoZoomScale)
        updateLandscapeCustomButtonsVisibility()
        updateBufferingUI()
        requestInterfaceOrientation(.landscapeRight)
    }

    private func exitFullscreenLandscape() {
        NSLayoutConstraint.deactivate(fullscreenConstraints)
        fullscreenConstraints.removeAll()

        if
            let originalSuperview = originalSuperviewForFullscreen,
            superview !== originalSuperview
        {
            removeFromSuperview()
            let insertIndex = min(max(0, originalSuperviewIndexForFullscreen), originalSuperview.subviews.count)
            originalSuperview.insertSubview(self, at: insertIndex)
        }

        NSLayoutConstraint.activate(storedSuperviewConstraints + storedSelfSizingConstraints)
        storedSuperviewConstraints.removeAll()
        storedSelfSizingConstraints.removeAll()

        originalSuperviewForFullscreen?.layoutIfNeeded()
        originalSuperviewForFullscreen = nil
        originalSuperviewIndexForFullscreen = 0

        fullscreenHostView?.layoutIfNeeded()
        fullscreenHostView = nil

        restoreNavigationBarIfNeeded()

        isExpandedFullscreen = false
        applyVideoZoomScale(minimumVideoZoomScale, animated: true)
        updateLandscapeCustomButtonsVisibility()
        updateBufferingUI()
        requestInterfaceOrientation(.portrait)
    }

    private func fullscreenPresentationHostView(fallback: UIView) -> UIView {
        if let navigationView = nearestViewController()?.navigationController?.view {
            return navigationView
        }
        if let viewControllerView = nearestViewController()?.view {
            return viewControllerView
        }
        if let window {
            return window
        }
        return fallback
    }

    private func constraintsForFullscreenExpansion(in hostView: UIView) -> [NSLayoutConstraint] {
        hostView.constraints.filter { constraint in
            let firstIsSelf = (constraint.firstItem as AnyObject?) === self
            let secondIsSelf = (constraint.secondItem as AnyObject?) === self
            guard firstIsSelf || secondIsSelf else { return false }

            let otherItem = firstIsSelf ? constraint.secondItem : constraint.firstItem
            if let otherView = otherItem as? UIView {
                return otherView === hostView
            }
            if let guide = otherItem as? UILayoutGuide {
                return guide.owningView === hostView
            }
            return otherItem == nil
        }
    }

    private func selfSizingConstraintsForFullscreen() -> [NSLayoutConstraint] {
        constraints.filter { constraint in
            let firstIsSelf = (constraint.firstItem as AnyObject?) === self
            let secondIsSelf = (constraint.secondItem as AnyObject?) === self
            guard firstIsSelf || secondIsSelf else { return false }

            // Deactivate only intrinsic sizing constraints on the player itself
            // (for example aspect-ratio constraints), not internal child layout constraints.
            return (constraint.firstItem as AnyObject?) === self
                && ((constraint.secondItem as AnyObject?) === self || constraint.secondItem == nil)
        }
    }

    private func requestInterfaceOrientation(_ orientation: UIInterfaceOrientation) {
        if #available(iOS 16.0, *) {
            guard let scene = window?.windowScene else { return }
            nearestViewController()?.setNeedsUpdateOfSupportedInterfaceOrientations()

            let targetMask: UIInterfaceOrientationMask = orientation.isLandscape ? .landscape : .portrait
            let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: targetMask)
            scene.requestGeometryUpdate(preferences) { [weak self] _ in
                self?.updateExpandButtonIcon()
            }
            return
        }

        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
        updateExpandButtonIcon()
    }

    private func restoreNavigationBarIfNeeded() {
        if
            let wasHidden = previousNavigationBarHidden,
            let navigationController = nearestViewController()?.navigationController
        {
            navigationController.setNavigationBarHidden(wasHidden, animated: false)
        }
        previousNavigationBarHidden = nil
    }

    private func updateExpandButtonIcon() {
        let role: CustomVideoPlayerIconRole = isExpandedFullscreen ? .collapse : .expand
        expandButton.setImage(resolvedControlImage(for: role), for: .normal)
    }

    private func updateVideoScaleButtonIcon() {
        let role: CustomVideoPlayerIconRole = (videoGravity == .resizeAspectFill) ? .videoScaleAspect : .videoScaleAspectFill
        videoScaleButton.setImage(resolvedControlImage(for: role), for: .normal)
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "00:00" }
        let value = Int(max(0, seconds.rounded(.down)))
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let remainingSeconds = value % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func selectedAudioDisplayName() -> String {
        guard
            let item = player?.currentItem,
            let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
            let option = item.currentMediaSelection.selectedMediaOption(in: group)
        else {
            return "Default"
        }
        return option.displayName
    }

    private func selectedSubtitleDisplayName() -> String {
        guard
            let item = player?.currentItem,
            let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
            let option = item.currentMediaSelection.selectedMediaOption(in: group)
        else {
            return "Off"
        }
        return option.displayName
    }

    private func selectedQualityDisplayName() -> String {
        let options = effectiveQualityOptions()
        return options.first(where: { $0.id == selectedQualityID })?.title
            ?? options.first?.title
            ?? CustomVideoQualityOption.auto.title
    }

    private func selectedPlaybackSpeedDisplayName() -> String {
        formatPlaybackSpeed(selectedPlaybackSpeed)
    }

    private func refreshMenus() {
        settingsButton.menu = buildSettingsMenu()
        ccButton.menu = buildSubtitleMenu(titlePrefix: "Subtitles")
    }

    private func buildSettingsMenu() -> UIMenu {
        let audioMenu = buildAudioMenu(titlePrefix: "Audio")
        let subtitleMenu = buildSubtitleMenu(titlePrefix: "Subtitle")
        let qualityMenu = buildQualityMenu()
        let playbackSpeedMenu = buildPlaybackSpeedMenu()

        return UIMenu(
            title: "",
            children: [audioMenu, subtitleMenu, qualityMenu, playbackSpeedMenu]
        )
    }

    private func buildAudioMenu(titlePrefix: String) -> UIMenu {
        guard
            let item = player?.currentItem,
            let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        else {
            let unavailableAction = UIAction(title: "Not Available", attributes: .disabled) { _ in }
            return UIMenu(title: "\(titlePrefix): N/A", children: [unavailableAction])
        }

        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        let actions = group.options.map { option in
            UIAction(
                title: option.displayName,
                state: option == selected ? .on : .off
            ) { [weak self] _ in
                self?.player?.currentItem?.select(option, in: group)
                self?.refreshMenus()
            }
        }

        return UIMenu(
            title: "\(titlePrefix): \(selectedAudioDisplayName())",
            children: actions
        )
    }

    private func buildSubtitleMenu(titlePrefix: String) -> UIMenu {
        guard
            let item = player?.currentItem,
            let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
        else {
            let off = UIAction(title: "Off", state: .on) { _ in }
            return UIMenu(title: "\(titlePrefix): Off", children: [off])
        }

        let selected = item.currentMediaSelection.selectedMediaOption(in: group)
        var actions: [UIAction] = []

        actions.append(
            UIAction(title: "Off", state: selected == nil ? .on : .off) { [weak self] _ in
                self?.player?.currentItem?.select(nil, in: group)
                self?.refreshMenus()
            }
        )

        for option in group.options {
            let action = UIAction(
                title: option.displayName,
                state: option == selected ? .on : .off
            ) { [weak self] _ in
                self?.player?.currentItem?.select(option, in: group)
                self?.refreshMenus()
            }
            actions.append(action)
        }

        return UIMenu(
            title: "\(titlePrefix): \(selectedSubtitleDisplayName())",
            children: actions
        )
    }

    private func buildQualityMenu() -> UIMenu {
        let options = effectiveQualityOptions()
        let actions = options.map { option in
            UIAction(
                title: option.title,
                state: option.id == selectedQualityID ? .on : .off
            ) { [weak self] _ in
                self?.selectedQualityID = option.id
                self?.applySelectedQuality()
                self?.refreshMenus()
            }
        }

        return UIMenu(
            title: "Quality: \(selectedQualityDisplayName())",
            children: actions
        )
    }

    private func buildPlaybackSpeedMenu() -> UIMenu {
        let actions = playbackSpeedOptions.map { speed in
            UIAction(
                title: formatPlaybackSpeed(speed),
                state: abs(speed - selectedPlaybackSpeed) < 0.001 ? .on : .off
            ) { [weak self] _ in
                self?.selectedPlaybackSpeed = speed
                self?.applySelectedPlaybackSpeed()
                self?.refreshMenus()
            }
        }

        return UIMenu(
            title: "Speed: \(selectedPlaybackSpeedDisplayName())",
            children: actions
        )
    }

    private func formatPlaybackSpeed(_ speed: Float) -> String {
        let value = Double(speed)
        if abs(value.rounded() - value) < 0.001 {
            return String(format: "%.0fx", value)
        }
        if abs((value * 10).rounded() - (value * 10)) < 0.001 {
            return String(format: "%.1fx", value)
        }
        return String(format: "%.2fx", value)
    }

    private func applySelectedQuality() {
        let selectedBitRate = effectiveQualityOptions()
            .first(where: { $0.id == selectedQualityID })?
            .peakBitRate ?? 0
        player?.currentItem?.preferredPeakBitRate = selectedBitRate
    }

    private func applySelectedPlaybackSpeed() {
        runOnMain { [weak self] in
            guard let self, let player = self.playerLayer.player else { return }
            guard !self.isApplyingPlaybackSpeed else { return }

            self.isApplyingPlaybackSpeed = true
            defer { self.isApplyingPlaybackSpeed = false }

            let speed = max(0.25, self.selectedPlaybackSpeed)
            player.defaultRate = speed

            guard player.currentItem?.status == .readyToPlay else { return }
            if player.timeControlStatus == .playing, abs(player.rate - speed) > 0.001 {
                player.pause()
                player.play()
            }
        }
    }
}
