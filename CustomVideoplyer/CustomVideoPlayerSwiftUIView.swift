//
//  CustomVideoPlayerSwiftUIView.swift
//  CustomVideoplyer
//
//  Created by Codex on 22/05/26.
//

import AVFoundation
import SwiftUI
import UIKit

@available(iOS 13.0, *)
public struct CustomVideoPlayerSwiftUIView: UIViewRepresentable {
    private let player: AVPlayer
    private let videoGravity: AVLayerVideoGravity
    private let qualityOptions: [CustomVideoQualityOption]?
    private let landscapeCustomButtons: [UIButton]?
    private let controlIcons: [CustomVideoPlayerIconRole: UIImage]?
    private let controlTintColors: [CustomVideoPlayerControlButton: UIColor]?
    private let liveAtEdgeColor: UIColor?
    private let liveGoLiveColor: UIColor?
    private let playerTitle: String?
    private let playerTitleColor: UIColor?
    private let playerTitleFont: UIFont?
    private let controlsGradientTopColor: UIColor?
    private let controlsGradientBottomColor: UIColor?
    private let onExpandTapped: (() -> Void)?
    private let onControlsVisibilityChanged: ((Bool) -> Void)?
    private let onStreamURLRefreshRequested: ((_ completion: @escaping (URL?) -> Void) -> Void)?

    public init(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        qualityOptions: [CustomVideoQualityOption]? = nil,
        landscapeCustomButtons: [UIButton]? = nil,
        controlIcons: [CustomVideoPlayerIconRole: UIImage]? = nil,
        controlTintColors: [CustomVideoPlayerControlButton: UIColor]? = nil,
        liveAtEdgeColor: UIColor? = nil,
        liveGoLiveColor: UIColor? = nil,
        playerTitle: String? = nil,
        playerTitleColor: UIColor? = nil,
        playerTitleFont: UIFont? = nil,
        controlsGradientTopColor: UIColor? = nil,
        controlsGradientBottomColor: UIColor? = nil,
        onExpandTapped: (() -> Void)? = nil,
        onControlsVisibilityChanged: ((Bool) -> Void)? = nil,
        onStreamURLRefreshRequested: ((_ completion: @escaping (URL?) -> Void) -> Void)? = nil
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.qualityOptions = qualityOptions
        self.landscapeCustomButtons = landscapeCustomButtons
        self.controlIcons = controlIcons
        self.controlTintColors = controlTintColors
        self.liveAtEdgeColor = liveAtEdgeColor
        self.liveGoLiveColor = liveGoLiveColor
        self.playerTitle = playerTitle
        self.playerTitleColor = playerTitleColor
        self.playerTitleFont = playerTitleFont
        self.controlsGradientTopColor = controlsGradientTopColor
        self.controlsGradientBottomColor = controlsGradientBottomColor
        self.onExpandTapped = onExpandTapped
        self.onControlsVisibilityChanged = onControlsVisibilityChanged
        self.onStreamURLRefreshRequested = onStreamURLRefreshRequested
    }

    private func applyExternalControlCustomization(to view: CustomVideoPlayerView) {
        for role in CustomVideoPlayerIconRole.allCases {
            view.setControlImage(controlIcons?[role], for: role)
        }

        for button in CustomVideoPlayerControlButton.allCases {
            view.setControlTintColor(controlTintColors?[button], for: button)
        }

        if let liveAtEdgeColor, let liveGoLiveColor {
            view.setLiveStatusTitleColors(atLiveEdge: liveAtEdgeColor, goLive: liveGoLiveColor)
        }

        view.setPlayerTitle(playerTitle)
        view.setPlayerTitleTextColor(playerTitleColor)
        view.setPlayerTitleFont(playerTitleFont)
        view.setControlsGradientColors(
            top: controlsGradientTopColor,
            bottom: controlsGradientBottomColor
        )
    }

    public func makeUIView(context: Context) -> CustomVideoPlayerView {
        let view = CustomVideoPlayerView(player: player, videoGravity: videoGravity)
        view.qualityOptions = qualityOptions ?? []
        view.setLandscapeCustomButtons(landscapeCustomButtons ?? [])
        applyExternalControlCustomization(to: view)
        view.onExpandTapped = onExpandTapped
        view.onControlsVisibilityChanged = onControlsVisibilityChanged
        view.onStreamURLRefreshRequested = onStreamURLRefreshRequested
        return view
    }

    public func updateUIView(_ uiView: CustomVideoPlayerView, context: Context) {
        uiView.player = player
        uiView.videoGravity = videoGravity
        uiView.qualityOptions = qualityOptions ?? []
        uiView.setLandscapeCustomButtons(landscapeCustomButtons ?? [])
        applyExternalControlCustomization(to: uiView)
        uiView.onExpandTapped = onExpandTapped
        uiView.onControlsVisibilityChanged = onControlsVisibilityChanged
        uiView.onStreamURLRefreshRequested = onStreamURLRefreshRequested
    }
}
