# E01 protocol observations

This document separates observations from hypotheses. UUIDs and command values are protocol identifiers, not device identities.

## Observed services

| Service | Characteristic | Observed role |
|---|---|---|
| `FD00` / `C2E6FD00-E966-1000-8000-BEF9C223DF6A` | `FD01` | primary notify |
| `FD00` | `FD02` | normal-data write |
| `FD00` | `FD03` | auxiliary notify/control |
| `AE00` | `AE01` | RCSP write |
| `AE00` | `AE02` | RCSP notify |

The implementation rejects services and characteristics outside its allowlists.

## Normal-data flow

- Bind request: command `0x60`.
- Explicit bind response: command `0x61`, checksummed, success state `0`.
- Badge information request/response: `0xC6/0xC7`.
- Video-dial update family: `0xC0` start, `0xC1` device request, `0xC2` data, `0xC3` progress, `0xC5` final result.

Frame construction, checksums and parsers are covered by unit tests in `Tests/CodexRingCoreTests`.

## RCSP flow

The `display` command uses the observed Jieli RCSP framing and large-file request/response exchange. After authentication it negotiates storage and transfer capability, answers device read requests in negotiated-MTU fragments with per-fragment CRC16, and waits for the device's explicit finish command. Authentication uses Jieli's publicly released Apache-2.0 `jl_auth_2.0.0.js`; see `THIRD_PARTY_NOTICES.md`.

## Live-device result

On the currently tested owner-controlled E01:

1. normal bind and badge identity parsing succeed;
2. RCSP authentication and storage negotiation succeed;
3. the device requests media in 3920-byte ranges;
4. the host splits each range by the negotiated 490-byte MTU and adds per-fragment CRC16;
5. the device requests the tail and then offset 0 for header verification;
6. an earlier visually confirmed run completed 229,798 media bytes and emitted `display_transfer_complete`;
7. the latest background-watcher run completed a 44,492-byte three-frame AVI, removed the previous generated file and then reported the same quota state as unchanged.

The latest watcher evidence was:

```text
display_sync_complete device=E01 codex_remaining=24 kimi_weekly_remaining=91 kimi_five_hour_remaining=82 file=CODEXB003.AVI transferred_media_bytes=44492
display_sync_cleanup_complete device=E01 file=CODEXA003.AVI
display_sync_unchanged codex_remaining=24 kimi_weekly_remaining=91 kimi_five_hour_remaining=82
```

This proves transfer completion, old-media cleanup and an unchanged follow-up cycle. The latest redesigned card still needs a separate visual readback; protocol completion alone is not documented as visual acceptance.

The normal-service `C0` video-dial path remains implemented for protocol study, but this firmware rejects its start header before issuing `C1`. An older attempt ended with `C5 reason 5`; that reason's general meaning has not been decoded. This is a historical result for an unused alternate path, not the current `display` blocker: the CLI now uses the verified RCSP media-transfer path.

## Not in scope

- No MAC address, serial number or QR binding URL is committed.
- No vendor APK, decompiled source or firmware is redistributed.
- No OTA command is exposed by the CLI.
- No compatibility claim is made for other circular displays that only look similar.
