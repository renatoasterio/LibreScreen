# Security Policy

## Supported versions

Only the latest release on the `main` branch receives security fixes.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's private vulnerability reporting on this repository
("Security" tab → "Report a vulnerability"). You will receive an acknowledgement
within 7 days and a fix or mitigation plan within 30 days for confirmed issues.

## Scope and design guarantees

LibreScreen is designed so that the following always hold. A violation of any of
them is considered a security bug:

- The app never opens network connections and never sends telemetry.
- Screen Recording, Camera and Microphone permissions are requested only in
  direct response to a user action that needs them, never at launch.
- Captured media is written only to folders chosen by the user (defaults:
  `~/Movies/LibreScreen` and `~/Pictures/LibreScreen`) using atomic writes.
- The app never spawns external processes and never loads code dynamically.
- Logs never contain window titles, file paths or other personal data in
  plain text (`os.Logger` with `privacy: .private`).
- The binary ships with the hardened runtime enabled and only the
  `camera` and `audio-input` entitlements.
