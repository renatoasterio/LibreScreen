# LibreScreen architecture

## Layers

```
┌──────────────────────────────────────────────────────────────────┐
│ Features (SwiftUI views, @MainActor ViewModels, AppKit panels)    │
├──────────────────────────────────────────────────────────────────┤
│ Infrastructure (ScreenCaptureKit · AVFoundation · Vision ·        │
│                 Pipeline · Storage · Hotkeys · Permissions)        │
├──────────────────────────────────────────────────────────────────┤
│ Domain (models · protocols · use cases)  — framework-free         │
└──────────────────────────────────────────────────────────────────┘
          App/AppContainer wires concrete services into protocols
```

- **Domain** owns the vocabulary: `CaptureSource`, `RecordingSettings`, `CameraOverlaySettings`,
  `CaptureItem`, `Annotation`, `LibreScreenError`, and the service protocols
  (`PermissionsChecking`, `ShareableContentProviding`, `RecordingCoordinating`, `Screenshotting`,
  `CameraCapturing`, `MicrophoneCapturing`, `SettingsStoring`, `CaptureStoring`, `HotkeyRegistering`).
  Use cases (`StartRecordingUseCase`, `TakeScreenshotUseCase`, …) compose protocols and contain the
  business rules (permission gating, output naming, history updates).
- **Infrastructure** implements the protocols. One folder per framework so that framework quirks stay
  contained. `Pipeline` holds the real-time path (`FrameClock`, `FrameCompositor`, `RecordingPipeline`).
- **Features** are vertical slices (`Hub`, `Recording`, `Screenshot`, `Editor`, `Settings`,
  `Permissions`). A feature has a ViewModel (`@MainActor @Observable`) that receives protocols in its
  initializer, SwiftUI views, and, when a floating window is needed, an `NSWindowController` hosting
  SwiftUI content. Views never talk to Infrastructure directly except for hardware preview views
  (`CameraPreviewView` reads frames from `CameraFrameSource`).
- **App** contains `LibreScreenApp` (scenes: `MenuBarExtra`, `Settings`), `AppDelegate` (lifecycle,
  activation policy, hotkeys, window controllers) and `AppContainer` (composition root).

Dependencies only point downwards. Tests replace Infrastructure with the fakes in
`LibreScreenTests/Fakes`.

## Threading model

| Component | Isolation | Notes |
|-----------|-----------|-------|
| ViewModels, window controllers, SwiftUI | `@MainActor` | All state the UI reads. |
| `ScreenCaptureEngine` (`SCStreamOutput`) | SCK delivery queue (serial) | Hands `ScreenFrame`/audio buffers to the pipeline, never touches UI. |
| `CameraCaptureService` | `camera.capture` serial queue | Runs Vision segmentation + Core Image blur, publishes `CameraFrame` to a latest-frame slot and an `AsyncStream` (`bufferingNewest(1)`) for previews. |
| `MicrophoneCaptureService` | `audio.capture` serial queue | Forwards `CMSampleBuffer`s to the pipeline and a level meter. |
| `RecordingPipeline` | `pipeline` serial queue | Owns `FrameClock`, `FrameCompositor`, `RecordingWriter`. Single writer of all mutable pipeline state. |
| `RecordingWriter` (`AVAssetWriter`) | Called only from the pipeline queue | Hardware H.264/HEVC + AAC. |
| Stores | `actor` (`CaptureStore`) / `@MainActor` (`SettingsStore`) | |

Rules: no `DispatchQueue.main` in Infrastructure; results travel back through `async` functions or
`AsyncStream`s. Frames cross queues wrapped in `@unchecked Sendable` structs whose buffers are never
mutated after creation.

## Recording pipeline

```
SCStream ──ScreenFrame──▶ latest screen slot ─┐
                                              │   FrameClock tick (1/fps)
AVCaptureSession(video) ─▶ Vision mask ─▶ blur ─▶ latest camera slot ─┤
                                              ▼
                                   FrameCompositor (Core Image / Metal)
                                   screen ⊕ camera bubble ─▶ CVPixelBuffer (pool)
                                              │
AVCaptureSession(audio) ──mic CMSampleBuffer──┼──▶ RecordingWriter (AVAssetWriter)
SCStream audio ──────system CMSampleBuffer────┘      video + mic track + system track
```

- The clock drives output, not the screen stream: ScreenCaptureKit only emits frames when content
  changes, but the webcam bubble must keep moving. When the camera is off and the screen did not change,
  the tick is skipped.
- All timestamps come from the host clock (`CMClockGetHostTimeClock`). Pausing accumulates an offset that
  is subtracted from every video and audio PTS after resume.
- The app's own floating panels are excluded twice: `NSWindow.sharingType = .none` and
  `SCContentFilter(... excludingApplications: [self])`.

## Recording state machine

`idle → preparing → countdown(n) → recording ⇄ paused → finishing → idle`, with `failed(error)` reachable
from any active state. `RecordingViewModel` owns the state; `RecordingPipeline` reports progress through
`RecordingEvent`s.

## Coordinate spaces

ScreenCaptureKit and `CGDisplayBounds` use a global space with the origin at the top-left of the main
display. `NSScreen`/AppKit use the bottom-left origin. `CaptureCoordinates` is the only place that
converts between them; everything in Domain is stored in the ScreenCaptureKit convention (points,
top-left origin). Pixel sizes are points × `backingScaleFactor` of the display that owns the source.

## Persistence

- `SettingsStore`: `AppSettings` as JSON in `UserDefaults`, validated (clamped) on load.
- `CaptureStore`: `[CaptureItem]` as JSON in `~/Library/Application Support/LibreScreen/captures.json`.
- Media: `~/Movies/LibreScreen` and `~/Pictures/LibreScreen` by default; user-configurable.

## Verification checklist (manual, hardware-dependent)

1. First launch asks for nothing. Pressing Record asks for Screen Recording; enabling the camera asks
   for Camera; enabling the microphone asks for Microphone.
2. Display, window and region recordings play in QuickTime at the expected pixel size.
3. Camera bubble position, shape and blur in the file match the on-screen preview.
4. Two-minute recording with pause/resume: duration equals recorded time, audio stays in sync.
5. Region screenshot on every display matches `screencapture -R` for the same rect.
6. After a one-minute recording, `leaks <pid>` reports zero leaks.
