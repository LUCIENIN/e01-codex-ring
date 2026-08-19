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
6. the latest verified run completed 229,798 media bytes and emitted `display_transfer_complete`.

The normal-service `C0` video-dial path remains implemented for protocol study, but this firmware rejects its start header before issuing `C1`. The CLI does not use that failed path for `display`.

## Not in scope

- No MAC address, serial number or QR binding URL is committed.
- No vendor APK, decompiled source or firmware is redistributed.
- No OTA command is exposed by the CLI.
- No compatibility claim is made for other circular displays that only look similar.
