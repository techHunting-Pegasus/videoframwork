//
//  ViewController.swift
//  UIKItexample
//
//  Created by Ishpreet singh on 22/05/26.
//

import AVFoundation
import CustomVideoplyer
import UIKit

final class ViewController: UIViewController {
    private let demoUR2L = URL(string: "https://nw18live.cdn.jio.com/bpk-tv/CNBC_TV18_NW18_MOB/output01/CNBC_TV18_NW18_MOB-audio_98834_eng=98800-video=2293600.m3u8")!
    private let demoURL2 = URL(string: "https://cnbc-live.akamaized.net/cnbc/cnbcSource/cnbc_480p/chunks.m3u8")!
    private let demoURL = URL(string: "https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8")!
   
    
    private lazy var player = AVPlayer(url: demoURL)

    private lazy var playerView: CustomVideoPlayerView = {
        let view = CustomVideoPlayerView(player: player, videoGravity: .resizeAspect)
        view.translatesAutoresizingMaskIntoConstraints = false
        // Empty means stream-derived dynamic quality options.
        view.qualityOptions = []
        configurePlayerCustomization(view)
        return view
    }()

    private let infoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14)
        label.text = "CustomVideoplyer demo (Live URL)\n- LIVE / GO LIVE handling\n- Play/Pause, DVR seek, ±10s (when available)\n- Expand toggles portrait/landscape"
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "UIKit Sample Player"
        view.backgroundColor = .systemBackground
        setupLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        player.play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.pause()
    }

    private func setupLayout() {
        view.addSubview(playerView)
        view.addSubview(infoLabel)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: safe.topAnchor, constant: 16),
            playerView.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            playerView.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            playerView.heightAnchor.constraint(equalTo: playerView.widthAnchor, multiplier: 9.0 / 16.0),

            infoLabel.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 16),
            infoLabel.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16)
        ])
        
    }
    private func configurePlayerCustomization(_ view: CustomVideoPlayerView) {
           // 1) ICONS (system + asset both supported)
           view.setControlImage(UIImage(systemName: "gobackward.10"), for: .backward)
           view.setControlImage(UIImage(named: "ic_play_custom")?.withRenderingMode(.alwaysTemplate), for: .play)
           view.setControlImage(UIImage(named: "ic_pause_custom")?.withRenderingMode(.alwaysTemplate), for: .pause)
           view.setControlImage(UIImage(systemName: "goforward.10"), for: .forward)
           view.setControlImage(UIImage(systemName: "captions.bubble.fill"), for: .cc)
           view.setControlImage(UIImage(systemName: "gearshape.fill"), for: .settings)
           view.setControlImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .expand)
           view.setControlImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .collapse)
           view.setControlImage(UIImage(systemName: "aspectratio.fill"), for: .videoScaleAspectFill)
           view.setControlImage(UIImage(systemName: "aspectratio"), for: .videoScaleAspect)

           // 2) COLORS
           view.setControlTintColor(.white, for: .backward)
           view.setControlTintColor(.systemYellow, for: .playPause)
           view.setControlTintColor(.white, for: .forward)
           view.setControlTintColor(.white, for: .cc)
           view.setControlTintColor(.white, for: .settings)
           view.setControlTintColor(.white, for: .expand)
           view.setControlTintColor(.white, for: .videoScale)

           // LIVE text colors
           view.setLiveStatusTitleColors(atLiveEdge: .systemRed, goLive: .systemOrange)

           // 3) Optional landscape-only custom buttons (0/1/2...)
           let bookmark = UIButton(type: .system)
           bookmark.setImage(UIImage(systemName: "bookmark.fill"), for: .normal)
           bookmark.tintColor = .white
           bookmark.addAction(UIAction { _ in
               print("Bookmark tapped")
           }, for: .touchUpInside)

           let share = UIButton(type: .system)
           share.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
           share.tintColor = .white
           share.addAction(UIAction { _ in
               print("Share tapped")
           }, for: .touchUpInside)

           view.setLandscapeCustomButtons([bookmark, share]) // [] or [bookmark] also valid
       }

}
