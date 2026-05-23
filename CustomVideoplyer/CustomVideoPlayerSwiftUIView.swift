//
//  CustomVideoPlayerSwiftUIView.swift
//  CustomVideoplyer
//
//  Created by Codex on 22/05/26.
//

import AVFoundation
import SwiftUI

@available(iOS 13.0, *)
public struct CustomVideoPlayerSwiftUIView: UIViewRepresentable {
    private let player: AVPlayer
    private let videoGravity: AVLayerVideoGravity
    private let qualityOptions: [CustomVideoQualityOption]?
    private let landscapeCustomButtons: [UIButton]?
    private let onExpandTapped: (() -> Void)?
    private let onStreamURLRefreshRequested: ((_ completion: @escaping (URL?) -> Void) -> Void)?

    public init(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        qualityOptions: [CustomVideoQualityOption]? = nil,
        landscapeCustomButtons: [UIButton]? = nil,
        onExpandTapped: (() -> Void)? = nil,
        onStreamURLRefreshRequested: ((_ completion: @escaping (URL?) -> Void) -> Void)? = nil
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.qualityOptions = qualityOptions
        self.landscapeCustomButtons = landscapeCustomButtons
        self.onExpandTapped = onExpandTapped
        self.onStreamURLRefreshRequested = onStreamURLRefreshRequested
    }

    public func makeUIView(context: Context) -> CustomVideoPlayerView {
        let view = CustomVideoPlayerView(player: player, videoGravity: videoGravity)
        view.qualityOptions = qualityOptions ?? []
        view.setLandscapeCustomButtons(landscapeCustomButtons ?? [])
        view.onExpandTapped = onExpandTapped
        view.onStreamURLRefreshRequested = onStreamURLRefreshRequested
        return view
    }

    public func updateUIView(_ uiView: CustomVideoPlayerView, context: Context) {
        uiView.player = player
        uiView.videoGravity = videoGravity
        uiView.qualityOptions = qualityOptions ?? []
        uiView.setLandscapeCustomButtons(landscapeCustomButtons ?? [])
        uiView.onExpandTapped = onExpandTapped
        uiView.onStreamURLRefreshRequested = onStreamURLRefreshRequested
    }
}
