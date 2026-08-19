# Changelog

## 0.2.0 — 2026-08-20

- Routed `display` through the RCSP media-transfer path verified on one owner-controlled 368×368 E01.
- Added a Codex + optional Kimi Code quota dashboard, sanitized Kimi cache and composite change detection.
- Added persistent watcher state, generated-media cleanup, bounded BLE recovery, known-device rescan and a LaunchAgent installer.
- Reduced the static MJPEG/YUVJ420P AVI to three frames; the latest device-completed artifact is 44,492 bytes.
- Added a read-only firmware probe and documented the remaining OTA, hardware-variant, visual-readback and power-cycle boundaries.

## 0.1.0 — 2026-08-19

- Added the macOS Swift CLI, circular Codex allowance renderer and bounded session reader.
- Added read-only E01 discovery, normal-service bind and badge identity parsing.
- Added tested normal-data, video-dial and RCSP frame/transfer primitives.
- Documented the unresolved live-device `C5 reason 5` result without claiming display success.
- Added privacy boundaries, third-party attribution, CI and public issue templates.
