# Changelog

All notable changes to LibreScreen are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-11

First public version.

### Added

- **Recording** of a full display, a single window or a custom area, with multi-monitor support, pause and resume,
  an optional countdown and a floating recording HUD.
- **Video options**: hardware H.264 or HEVC, MP4 or MOV, 30 or 60 fps, three quality levels, native Retina or 1×
  resolution, and cursor visibility.
- **Webcam bubble** composed live into the recording: circle or rounded rectangle, three sizes, four corners,
  mirroring, border and shadow.
- **Camera background**: blur or a custom image behind you, using on-device person segmentation.
- **Audio**: system audio and microphone written as separate tracks.
- **Screenshots** of a display, a window or an area at full Retina resolution, as PNG or JPEG, with copy to the
  clipboard and a floating thumbnail.
- **Annotation editor**: arrow, line, rectangle, ellipse, freehand, text, highlighter, pixelate, numbered steps and
  crop, with undo and redo, and copy, share or save.
- **Global shortcuts** for every capture action, rebindable in Settings, plus menu bar quick actions.
- **Permissions flow** that asks for Screen Recording, Camera and Microphone only when a feature needs them.
- **Localization** in Portuguese (Brazil) and English.
- **Liquid Glass** interface on macOS 26 with a fallback on macOS 15.
- **Tooling**: `Makefile`, XcodeGen project, CI (format, lint, build, tests, safety audit), release script and the
  `code-audit` skill.

[0.1.0]: https://github.com/renatoasterio/LibreScreen/releases/tag/v0.1.0
