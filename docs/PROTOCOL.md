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

The repository contains parsers and encoders for the observed Jieli RCSP framing and large-file request/response exchange. Authentication uses Jieli's publicly released Apache-2.0 `jl_auth_2.0.0.js`; see `THIRD_PARTY_NOTICES.md`.

## Known failure

On the currently tested owner-controlled E01:

1. advertisement and connection can be intermittent;
2. normal bind can succeed;
3. badge identity can be read;
4. a video-dial start attempt is rejected with `C5 reason 5`;
5. trying several candidate slot values did not turn it into success.

The meaning of reason `5` is not confirmed. Do not label it as a specific firmware error without a primary source or a controlled experiment.

## Not in scope

- No MAC address, serial number or QR binding URL is committed.
- No vendor APK, decompiled source or firmware is redistributed.
- No OTA command is exposed by the CLI.
- No compatibility claim is made for other circular displays that only look similar.
