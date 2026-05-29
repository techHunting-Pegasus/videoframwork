//
//  ContentView.swift
//  swiftUiexample
//
//  Created by Ishpreet singh on 27/05/26.
//

import AVFoundation
import Combine
import CustomVideoplyer
import SwiftUI
import UIKit

@MainActor
final class SwiftUIPlayerDemoViewModel: ObservableObject {
    enum VideoSource: String, CaseIterable, Identifiable {
        case live
        case vod

        var id: String { rawValue }

        var title: String {
            switch self {
            case .live:
                return "Live"
            case .vod:
                return "VOD"
            }
        }
    }

    let liveURL =  URL(string: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8")!

    let vodURL = URL(string: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8")!

    let player: AVPlayer

    @Published var selectedSource: VideoSource = .live
    @Published var useManualQualityOptions = false
    @Published var statusText = "Dynamic quality enabled. Stream se options auto-fetch honge."

    private(set) var currentURL: URL

    lazy var landscapeButtons: [UIButton] = {
        [
            makeLandscapeButton(
                systemName: "bookmark.fill",
                accessibilityLabel: "Bookmark"
            ) { [weak self] in
                self?.statusText = "Bookmark tapped (landscape custom button)."
            },
            makeLandscapeButton(
                systemName: "square.and.arrow.up",
                accessibilityLabel: "Share"
            ) { [weak self] in
                self?.statusText = "Share tapped (landscape custom button)."
            }
        ]
    }()

    let controlIcons: [CustomVideoPlayerIconRole: UIImage] = {
        var icons: [CustomVideoPlayerIconRole: UIImage] = [:]
        if let image = UIImage(systemName: "gobackward.10") { icons[.backward] = image }
        if let image = UIImage(systemName: "play.fill") { icons[.play] = image }
        if let image = UIImage(systemName: "pause.fill") { icons[.pause] = image }
        if let image = UIImage(systemName: "goforward.10") { icons[.forward] = image }
        if let image = UIImage(systemName: "captions.bubble.fill") { icons[.cc] = image }
        if let image = UIImage(systemName: "gearshape.fill") { icons[.settings] = image }
        if let image = UIImage(systemName: "arrow.up.left.and.arrow.down.right") { icons[.expand] = image }
        if let image = UIImage(systemName: "arrow.down.right.and.arrow.up.left") { icons[.collapse] = image }
        if let image = UIImage(systemName: "aspectratio") { icons[.videoScaleAspect] = image }
        if let image = UIImage(systemName: "aspectratio.fill") { icons[.videoScaleAspectFill] = image }
        return icons
    }()

    let controlTintColors: [CustomVideoPlayerControlButton: UIColor] = [
        .backward: .white,
        .playPause: .systemYellow,
        .forward: .white,
        .cc: .white,
        .settings: .white,
        .expand: .white,
        .videoScale: .white
    ]

    var qualityOptions: [CustomVideoQualityOption] {
        guard useManualQualityOptions else { return [] } // [] => dynamic from stream

        return [
            .auto,
            CustomVideoQualityOption(id: "q_480", title: "480p", peakBitRate: 1_000_000),
            CustomVideoQualityOption(id: "q_720", title: "720p", peakBitRate: 2_000_000),
            CustomVideoQualityOption(id: "q_1080", title: "1080p", peakBitRate: 4_000_000)
        ]
    }

    init() {
        currentURL = liveURL
        player = AVPlayer(url: liveURL)
        player.automaticallyWaitsToMinimizeStalling = true
    }

    func startPlayback() {
        player.play()
    }

    func pausePlayback() {
        player.pause()
    }

    func switchSource(to source: VideoSource) {
        let nextURL = url(for: source)
        guard nextURL != currentURL else { return }

        currentURL = nextURL
        player.replaceCurrentItem(with: AVPlayerItem(url: nextURL))
        player.play()
        statusText = "\(source.title) source loaded."
    }

    func handleQualityModeChanged() {
        if useManualQualityOptions {
            statusText = "Manual quality options active (Auto/480p/720p/1080p)."
        } else {
            statusText = "Dynamic quality enabled. Stream se options auto-fetch honge."
        }
    }

    func handleExpandTapped() {
        statusText = "Expand tapped: landscape mode toggle ho gaya."
    }

    func handleStreamRefreshRequest(_ completion: @escaping (URL?) -> Void) {
        completion(currentURL)
        statusText = "Stream refresh request handled with current URL."
    }

    private func url(for source: VideoSource) -> URL {
        switch source {
        case .live:
            return liveURL
        case .vod:
            return vodURL
        }
    }

    private func makeLandscapeButton(
        systemName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.tintColor = .white
        button.accessibilityLabel = accessibilityLabel
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}

struct ContentView: View {
    @StateObject private var viewModel = SwiftUIPlayerDemoViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CustomVideoPlayerSwiftUIView(
                        player: viewModel.player,
                        videoGravity: .resizeAspect,
                        qualityOptions: viewModel.qualityOptions,
                        landscapeCustomButtons: viewModel.landscapeButtons,
                        controlIcons: viewModel.controlIcons,
                        controlTintColors: viewModel.controlTintColors,
                        liveAtEdgeColor: .systemRed,
                        liveGoLiveColor: .systemOrange,
                        onExpandTapped: viewModel.handleExpandTapped,
                        onStreamURLRefreshRequested: viewModel.handleStreamRefreshRequest
                    )
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )


                }
            }
            .navigationTitle("SwiftUI Player Demo")
            .background(Color.black.ignoresSafeArea())
        }
        .onAppear {
            viewModel.startPlayback()
        }
        .onDisappear {
            viewModel.pausePlayback()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
