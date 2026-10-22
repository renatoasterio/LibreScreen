// LibreScreen
// Copyright (c) 2026 Renato Asterio
// Licensed under the PolyForm Noncommercial License 1.0.0

import AVFoundation

/// Camera and microphone discovery. Enumeration never prompts for a permission.
struct MediaDeviceService: MediaDeviceProviding {
    func cameras() -> [MediaDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return Self.sorted(session.devices.map { device in
            MediaDevice(
                id: device.uniqueID,
                name: device.localizedName,
                kind: .camera,
                isBuiltIn: device.deviceType == .builtInWideAngleCamera
            )
        })
    }

    func microphones() -> [MediaDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return Self.sorted(session.devices.map { device in
            MediaDevice(
                id: device.uniqueID,
                name: device.localizedName,
                kind: .microphone,
                isBuiltIn: device.deviceType == .microphone && device.localizedName.localizedCaseInsensitiveContains("MacBook")
            )
        })
    }

    private static func sorted(_ devices: [MediaDevice]) -> [MediaDevice] {
        devices.sorted { lhs, rhs in
            if lhs.isBuiltIn != rhs.isBuiltIn {
                return lhs.isBuiltIn
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
