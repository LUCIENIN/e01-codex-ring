# Contributing

Contributions are welcome when they preserve the evidence and privacy boundaries.

## Before opening a pull request

```bash
swift test
git diff --check
```

Keep changes small and add a fixture-driven test for protocol parsing or encoding changes.

## Device reports

Include:

- command stage and error enum;
- anonymized firmware/protocol/model fields;
- returned command and reason code;
- whether the display visibly changed.

Remove:

- MAC addresses, serial numbers and QR URLs;
- Codex prompts, messages, session paths and account data;
- API keys, cookies and vendor firmware/APK files.

Use only hardware you own or are authorized to test. A successful CoreBluetooth write callback is transport evidence, not proof that the screen accepted the content.
