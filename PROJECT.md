# Project plan

## Goal

让 E01/ZRun 圆形 BLE 胸牌稳定显示由用户自己的程序生成的 368×368 内容，并且每个成功结论都有设备响应和肉眼回读两层证据。

## Current status

| Area | Status | Acceptance evidence |
|---|---|---|
| Circular Codex allowance renderer | Done | PNG generated; renderer tests pass |
| Read-only BLE discovery | Done | `FD00` advertisement is required |
| Normal-service bind | Done | checksummed `0x61`, state `0` |
| Badge/firmware identity parsing | Done | parser tests and bind output fields |
| Media/protocol encoders | Done at unit level | deterministic frame/CRC tests |
| Live custom-content write | Blocked | device returns `C5 reason 5` |
| Firmware replacement | Not started | no exact official image or rollback proof |

## Milestones

### v0.2 — First verified live display

- Reduce `C5 reason 5` to one confirmed cause.
- Obtain `C5 reason 0` on an owner-controlled device.
- Verify the visible content matches the generated PNG.
- Record only anonymized device identity and protocol trace.

### v0.3 — Reusable display SDK

- Separate renderer, session source, media encoder and BLE transport.
- Add a fixture-driven transport simulator.
- Support a generic JSON data source instead of only Codex sessions.

### v1.0 — Safe operator workflow

- Stable reconnect and refresh loop.
- Explicit device selection when multiple badges advertise.
- Recovery instructions and compatibility matrix.
- No firmware path unless exact image provenance and rollback are verified.

## Definition of done

A physical write is complete only when all of these are true:

1. The intended device was selected without publishing its MAC.
2. Bind and device identity were parsed successfully.
3. Transfer ended with the device's explicit success result.
4. The new content was visually confirmed on the round screen.
5. A later reconnect did not leave the badge unusable.
