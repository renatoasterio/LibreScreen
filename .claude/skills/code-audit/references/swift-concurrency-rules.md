# Swift concurrency rules — LibreScreen code audit

**Scope.** Swift 6 language mode with strict concurrency is on, so most data races are compile errors; this checklist targets the places where code can still be wrong while compiling: the escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, `assumeIsolated`), the boundary between actor-isolated code and the Dispatch-based capture world (`SCStreamOutput`, `AVCapture*DataOutputSampleBufferDelegate`, the `FrameClock` `DispatchSourceTimer`, the `RecordingPipeline` serial queue), blocking the main thread, and backpressure between 30–60 fps producers and slower consumers (encoder, Vision, the SwiftUI preview). Layer expectations: `Features/` ViewModels are `@MainActor @Observable`; `Domain/` is `Sendable` value types and protocols; `Infrastructure/` is actors, queue-confined classes and `nonisolated` delegate entry points that never touch the main queue directly.

## 1. **ViewModels and everything that touches AppKit or SwiftUI are `@MainActor`**

SwiftUI reads `@Observable` state on the main actor; a ViewModel without `@MainActor` lets Infrastructure write it from a capture queue, and `NSPanel`/`NSWindow` calls off the main thread corrupt AppKit state. A missing annotation usually surfaces as a wall of `Sendable` errors that then get silenced with escape hatches.

Grep: `grep -rn -B1 '@Observable' Features | grep -v '@MainActor'`; `final class \w+(Controller|Panel|Window|Overlay)\b` without `@MainActor`.

Wrong:
```swift
@Observable final class RecorderViewModel {         // not isolated
    var elapsed: TimeInterval = 0                   // written from the FrameClock queue
}
```
Right:
```swift
@MainActor @Observable final class RecorderViewModel {
    private(set) var elapsed: TimeInterval = 0
    func start() { tickTask = Task { for await t in recorder.elapsedTicks { elapsed = t } } }   // on main
}
```

## 2. **Shared mutable state outside the main actor is an `actor` or is confined to one serial queue**

A `final class` with `var`s read by the main actor and written by a capture queue is a data race even when the compiler has been persuaded to accept it. Actors are right for control-plane state (settings, recording state machine, device lists); the per-frame hot path stays on the pipeline queue (rule 11) because an actor hop per frame is not free.

Grep: `final class \w+` in `Infrastructure/` containing `\bvar\b` but neither `@MainActor`, `actor `, nor a `private let queue`; every `@unchecked Sendable` (rule 4).

Wrong:
```swift
final class RecordingStateStore: @unchecked Sendable {
    var state: RecordingState = .idle               // mutated from main and from the pipeline queue
}
```
Right:
```swift
actor RecordingStateStore {
    private(set) var state: RecordingState = .idle
    func transition(to new: RecordingState) throws { … }
}
// or: a value snapshot (`RecordingSettings: Sendable`) passed into start() and never mutated afterwards
```

## 3. **Capture delegate callbacks are `nonisolated` entry points on their own serial queues**

`SCStreamOutput.stream(_:didOutputSampleBuffer:of:)` and `captureOutput(_:didOutput:from:)` (video and audio) arrive on the queue passed at registration. Swift 6 refuses a `@MainActor` class as the delegate (the requirement is nonisolated), and the usual "fix" (`@preconcurrency` conformance or `MainActor.assumeIsolated`) either traps at runtime or serialises capture through the UI thread.

Grep: `@MainActor` on a type that conforms to `SCStreamOutput|SampleBufferDelegate`; `@preconcurrency (SCStreamOutput|AVCapture\w+Delegate)`; `assumeIsolated` inside `didOutputSampleBuffer|captureOutput`.

Wrong:
```swift
@MainActor final class ScreenCaptureService: NSObject, @preconcurrency SCStreamOutput {
    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of t: SCStreamOutputType) {
        latestFrame = sb                            // main-actor assumption checked on a capture queue
    }
}
```
Right:
```swift
final class ScreenFrameOutput: NSObject, SCStreamOutput, Sendable {
    private let pipeline: RecordingPipeline         // Sendable, queue-confined
    nonisolated func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of t: SCStreamOutputType) {
        pipeline.submit(sb, kind: t)                // stays on the sampleHandlerQueue; no actor hop
    }
}
```

## 4. **`@unchecked Sendable` only on immutable-after-creation frame wrappers, with the invariant written down**

`CVPixelBuffer`, `CMSampleBuffer` and `CIImage` are not marked `Sendable` by the SDK, yet frames must cross from the capture queue to the pipeline and the preview. A wrapper is sound when nothing writes the buffer after hand-over and the wrapper has only `let`s. The same attribute on a class with `var`s, or on `AVAssetWriter`, `AVCaptureSession` or `CIFilter`, hides the race instead of removing it.

Grep: `@unchecked Sendable` — for each hit check: `struct` or `final class`, only `let` stored properties, a comment stating the invariant, no session/writer/filter inside.

Wrong:
```swift
final class CaptureContext: @unchecked Sendable {   // silences the compiler, keeps the race
    var writer: AVAssetWriter?
    var isRecording = false
}
```
Right:
```swift
/// Read-only frame handed from the capture queue to the pipeline. The pixel buffer is never written
/// after creation (ScreenCaptureKit and the pool treat it as finished); this type holds only `let`s.
struct Frame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    let contentRect: CGRect
}
```

## 5. **Never block the main thread: no semaphores, `DispatchGroup.wait`, `sleep` or `queue.sync` from `@MainActor` code**

ScreenCaptureKit and AVFoundation completion handlers may need the main thread; waiting for them on main deadlocks the app with the recording indicator on. `AVCaptureSession.startRunning()`/`stopRunning()` block for hundreds of milliseconds and belong on the session queue.

Grep: `DispatchSemaphore|\.wait\(|DispatchGroup\(\)|Thread\.sleep|usleep\(|\bsleep\(|RunLoop\.(main|current)\.run|\.sync \{`; `startRunning\(\)|stopRunning\(\)` inside `@MainActor` types.

Wrong:
```swift
@MainActor func shareableWindows() -> [SCWindow] {
    let sem = DispatchSemaphore(value: 0); var windows: [SCWindow] = []
    SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, _ in
        windows = c?.windows ?? []; sem.signal()
    }
    sem.wait()                                      // deadlock candidate
    return windows
}
```
Right:
```swift
func shareableWindows() async throws -> [SCWindow] {
    try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).windows
}
```

## 6. **`Task.detached` only for CPU-heavy, self-contained work returning a `Sendable` result; never for UI**

`Task {}` inherits the actor and priority of its creator, which is what ViewModels want. `Task.detached` drops both, so UI mutations inside it are errors or hidden main-actor hops, and a detached task per frame is unbounded parallelism. Thumbnail generation for a finished recording is a legitimate use; per-frame segmentation is not (it runs on the pipeline queue).

Grep: `Task\.detached` — each hit must be outside `Features/`, outside frame callbacks, and awaited by its caller.

Wrong:
```swift
Task.detached { await MainActor.run { self.hud.update(elapsed) } }   // pointless hop, lost priority
```
Right:
```swift
let thumbnail = await Task.detached(priority: .utility) { [url] in
    try? ThumbnailRenderer.render(url, at: .zero)   // pure function returning a Sendable image wrapper
}.value
```

## 7. **Long loops check for cancellation; cancellation stops the capture, not just the loop**

`for await` loops over frames, thumbnail generation and export loops keep running after the window closes unless they observe cancellation. `Task.cancel()` is cooperative; without `checkCancellation`/`isCancelled` the work, and the buffers it retains, continue.

Grep: `for await` whose body lacks `Task\.isCancelled|checkCancellation`; long-running captures started from a `Task` without `withTaskCancellationHandler`.

Wrong:
```swift
func exportThumbnails(_ times: [CMTime]) async throws {
    for t in times { try await generate(t) }        // ignores cancellation
}
```
Right:
```swift
func exportThumbnails(_ times: [CMTime]) async throws {
    for t in times {
        try Task.checkCancellation()
        try await generate(t)
    }
}
// preview loop: for await frame in previews { guard !Task.isCancelled else { break }; show(frame) }
```

## 8. **`AsyncStream`s for previews use `.bufferingNewest(1)`; frame callbacks yield into them synchronously, never one `Task` per frame; the recording path does not use `AsyncStream`**

The default policy is `.unbounded`: a SwiftUI preview that falls behind at 60 fps accumulates frames (and their IOSurfaces) without limit. `.bufferingNewest(1)` makes the consumer always see the latest frame and never back-pressure the capture. Spawning `Task { @MainActor in … }` inside `captureOutput` is the same bug in another shape: 60 tasks a second with no ordering guarantee and no limit. Frames that must not be dropped (the encoder) go through the pipeline queue with explicit `isReadyForMoreMediaData` checks, not through a stream.

Grep: `AsyncStream<|AsyncStream\(|makeStream\(` without `bufferingPolicy:`; `\.unbounded`; `Task \{|Task\.detached` inside `didOutputSampleBuffer|captureOutput\(`; `AsyncStream` in the writer path.

Wrong:
```swift
let previews = AsyncStream<PreviewFrame> { continuation in      // .unbounded by default
    capture.onPreview = { continuation.yield($0) }
}
nonisolated func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
    Task { @MainActor in viewModel.previewImage = CIImage(cvPixelBuffer: sb.imageBuffer!) }   // 60 unordered tasks/s
}
```
Right:
```swift
let (previews, continuation) = AsyncStream.makeStream(of: PreviewFrame.self, bufferingPolicy: .bufferingNewest(1))
continuation.onTermination = { @Sendable _ in capture.stopPreview() }   // consumer gone -> producer stops
nonisolated func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
    guard let pb = sb.imageBuffer else { return }
    continuation.yield(PreviewFrame(pixelBuffer: pb, time: sb.presentationTimeStamp))   // slow consumer drops old frames only
}
```

## 9. **No `DispatchQueue.main` in `Infrastructure/`; results come back through `async` functions, `AsyncStream`s or `@MainActor` closures**

Infrastructure should not know where its consumer lives. `DispatchQueue.main.async` inside a service bypasses actor isolation (the compiler cannot see that the block runs on main), hides ordering bugs and makes the service untestable without a run loop. The same applies to the `FrameClock` `DispatchSourceTimer` handler: it is a plain closure on a background queue, so it publishes ticks to the pipeline and never touches a ViewModel or panel; the HUD's elapsed-time label is driven by a main-actor `Task` loop.

Grep: `DispatchQueue\.main|MainActor\.run|RunLoop\.main|performSelector\(onMainThread` under `Infrastructure/` (expect zero hits); `setEventHandler \{` whose body references a ViewModel, `Panel`, `NSView` or `NSWindow`.

Wrong:
```swift
// Infrastructure/Capture/ScreenRecorder.swift
nonisolated func stream(_ s: SCStream, didStopWithError error: Error) {
    DispatchQueue.main.async { self.onStopped?(error) }        // isolation invisible to the compiler
}
timer.setEventHandler { hudPanel.elapsedLabel.stringValue = format(elapsed) }   // AppKit off main
```
Right:
```swift
// Infrastructure exposes events; the ViewModel consumes them on its own actor
let events: AsyncStream<RecorderEvent>                         // yield(.stopped(error)) from any queue
// or an isolated callback type:
func start(onStop: @escaping @MainActor @Sendable (RecorderError) -> Void)   // invoked as Task { await onStop(e) }
timer.setEventHandler { [weak self] in self?.pipeline.tick(at: .now()) }     // FrameClock: pipeline-queue work only
```

## 10. **Every Domain model and protocol is `Sendable`; no AppKit/AVFoundation types in Domain**

Domain values cross from ViewModels (main actor) to actors and queues on every start/stop; a non-`Sendable` model is a compile error at the first boundary and gets "fixed" with `@unchecked`. `NSImage`, `AVCaptureDevice` and `SCWindow` are not `Sendable` and do not belong in Domain anyway.

Grep: `^\s*(public )?(struct|enum|final class|protocol) \w+` lines in `Domain/` that do not contain `Sendable`; `import (AppKit|AVFoundation|ScreenCaptureKit|CoreImage)` in `Domain/`.

Wrong:
```swift
// Domain/Models/RecordingSettings.swift
import AppKit
struct RecordingSettings { var outputDirectory: URL; var watermark: NSImage?; var source: SCWindow? }
```
Right:
```swift
struct RecordingSettings: Sendable, Codable, Equatable {
    var outputDirectory: URL
    var fps: Int
    var source: CaptureSource
}
enum CaptureSource: Sendable, Codable, Equatable {
    case display(CGDirectDisplayID), window(CGWindowID), region(CGRect, CGDirectDisplayID)
}
protocol ScreenRecording: Sendable { func start(_ s: RecordingSettings) async throws; func stop() async throws -> URL }
```

## 11. **Latest-frame slots are protected by a `Mutex` or owned by the single pipeline queue; never a bare `var`**

The preview bridge, the segmentation mask cache and the "last good frame" follow the same pattern: written by one queue, read by another. A plain `var` behind `@unchecked Sendable` gives torn reads and double-releases of `CVPixelBuffer`s. `Synchronization.Mutex` (macOS 15) is the lightest correct tool; `dispatchPrecondition` makes queue ownership checkable in Debug.

Grep: `nonisolated\(unsafe\) var`; `@unchecked Sendable` together with `var`; `latest\w*:` in a type without `Mutex|OSAllocatedUnfairLock|dispatchPrecondition`.

Wrong:
```swift
final class PreviewBridge: @unchecked Sendable {
    nonisolated(unsafe) var latest: CVPixelBuffer?   // written on the capture queue, read on main
}
```
Right:
```swift
import Synchronization
final class LatestFrameSlot: Sendable {
    private let slot = Mutex<Frame?>(nil)
    func publish(_ frame: Frame) { slot.withLock { $0 = frame } }
    func take() -> Frame? { slot.withLock { let f = $0; $0 = nil; return f } }
}
// queue-owned alternative: each mutating method starts with dispatchPrecondition(condition: .onQueue(queue))
```

## 12. **The `RecordingPipeline` queue is the only owner of writer state; `stop()` drains it through a continuation**

`AVAssetWriter` is not thread-safe; `finishWriting` called from main while the queue is still appending corrupts the file. The pipeline is `Sendable` by confinement (a documented `@unchecked Sendable` whose every entry point hops onto the queue) and exposes `async` start/stop that resolve when the queue has really finished.

Grep: `finishWriting|startWriting|\.append\(` outside the pipeline file; `withCheckedContinuation|withCheckedThrowingContinuation` expected in the pipeline's `stop`.

Wrong:
```swift
@MainActor func stopTapped() { pipeline.writer.finishWriting { } }   // races with append on the queue
```
Right:
```swift
func stop() async throws -> URL {
    try await withCheckedThrowingContinuation { cont in
        queue.async { self.finishOnQueue { cont.resume(with: $0) } }   // after the last append
    }
}
```

## 13. **Escape hatches (`nonisolated(unsafe)`, `MainActor.assumeIsolated`, `@preconcurrency`) each carry a comment that proves the assumption**

These disable checking, so the audit treats an undocumented hatch as a defect. `assumeIsolated` is right only where the framework documents the thread: the Carbon hot-key handler installed on `GetApplicationEventTarget()` fires on the main thread, and so do `NSWindowDelegate` callbacks. It is wrong in anything reached from a capture or pipeline queue.

Grep: `nonisolated\(unsafe\)|assumeIsolated|assertIsolated|@preconcurrency` — each hit needs a comment on the line above naming the guarantee.

Wrong:
```swift
nonisolated func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of t: SCStreamOutputType) {
    MainActor.assumeIsolated { viewModel.frameCount += 1 }   // traps: the capture queue is not main
}
```
Right:
```swift
// Carbon delivers hot-key events on the main thread because the handler is installed on the
// application event target; assumeIsolated is runtime-checked and would trap if that ever changed.
let handler: EventHandlerUPP = { _, event, _ in
    MainActor.assumeIsolated { HotKeyService.shared.dispatch(event) }
    return noErr
}
```

## Severity guide

| Severity | Classify here when… | Typical findings from this file |
|---|---|---|
| High | A real data race or deadlock is possible, or the frame pipeline can grow without bound | `@unchecked Sendable` on a class with `var`s (#4); `nonisolated(unsafe) var` shared across queues (#11); semaphore/`sync`/`sleep` on main (#5); `assumeIsolated` in a capture callback (#3, #13); writer state touched outside the pipeline queue (#12); `.unbounded` stream or `Task` per frame in the frame path (#8) |
| Medium | Isolation is wrong but currently masked, or work outlives its owner | ViewModel or AppKit controller missing `@MainActor` (#1); mutable class instead of actor/queue confinement (#2); `DispatchQueue.main` in Infrastructure (#9); `Task.detached` for UI (#6); missing cancellation checks (#7); non-`Sendable` Domain model or AppKit import in Domain (#10); `@preconcurrency` conformance (#3); timer handler touching UI or ViewModel state (#9) |
| Low | Correct but undocumented or stylistic | Provably correct `assumeIsolated` without a comment (#13); redundant `nonisolated`; `Task.detached` for CPU work that could be structured (`async let`/task group) (#6) |
