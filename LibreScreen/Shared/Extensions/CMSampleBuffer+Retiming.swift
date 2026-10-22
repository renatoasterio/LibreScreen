// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import CoreMedia

extension CMSampleBuffer {
    /// A copy whose timestamps are moved earlier by `offset`. Used to remove paused time from audio.
    func shifted(byNegative offset: CMTime) -> CMSampleBuffer? {
        guard offset != .zero else { return self }
        do {
            let timings = try sampleTimingInfos().map { timing -> CMSampleTimingInfo in
                var copy = timing
                copy.presentationTimeStamp = timing.presentationTimeStamp - offset
                if timing.decodeTimeStamp.isValid {
                    copy.decodeTimeStamp = timing.decodeTimeStamp - offset
                }
                return copy
            }
            return try CMSampleBuffer(copying: self, withNewTiming: timings)
        } catch {
            return nil
        }
    }
}
