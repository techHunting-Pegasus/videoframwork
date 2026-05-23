# ``CustomVideoplyer``

A lightweight video player framework that works in both UIKit and SwiftUI.

## Overview

This module exposes:

- `CustomVideoPlayerView` for UIKit
- `CustomVideoPlayerSwiftUIView` for SwiftUI

### Built-in Custom Controls

- No default AVPlayer controls
- Play/Pause
- 10s forward/backward
- Current time + seek bar + total duration
- `CC` button for subtitle selection
- `Settings` context menu with dynamic:
  - Audio options
  - Subtitle options
  - Quality options (stream-derived by default)
- Expand button callback

## UIKit Usage

```swift
import AVFoundation
import CustomVideoplyer

let url = URL(string: "https://example.com/video.mp4")!
let player = AVPlayer(url: url)

let videoView = CustomVideoPlayerView(player: player)
videoView.videoGravity = .resizeAspectFill

// Default behavior: quality options fetched dynamically from stream
videoView.qualityOptions = []

// Optional override: user-provided quality options
videoView.qualityOptions = [
    .auto,
    CustomVideoQualityOption(id: "360p", title: "360p", peakBitRate: 800_000),
    CustomVideoQualityOption(id: "720p", title: "720p", peakBitRate: 2_500_000),
    CustomVideoQualityOption(id: "1080p", title: "1080p", peakBitRate: 5_000_000)
]
videoView.onExpandTapped = {
    // Handle fullscreen transition
}
videoView.play()
```

## SwiftUI Usage

```swift
import AVFoundation
import SwiftUI
import CustomVideoplyer

struct PlayerScreen: View {
    private let player = AVPlayer(url: URL(string: "https://example.com/video.mp4")!)

    var body: some View {
        CustomVideoPlayerSwiftUIView(
            player: player,
            videoGravity: .resizeAspect,
            // qualityOptions: nil -> stream-derived dynamic options
            qualityOptions: nil,
            onExpandTapped: {
                // Handle fullscreen transition
            }
        )
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}
```

## Topics

### Views

- ``CustomVideoPlayerView``
- ``CustomVideoPlayerSwiftUIView``
- ``CustomVideoQualityOption``
