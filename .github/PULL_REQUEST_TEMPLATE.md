## What & why

<!-- What does this change and why? Link any issue. -->

## Checklist

- [ ] Built with `scripts/build_app.sh Release` (not `swift build`)
- [ ] Ran the headless self-test: `dist/Talkink.app/Contents/MacOS/Soyle --selftest <16k-mono.wav>`
- [ ] Exercised push-to-talk → transcribe → paste, and the History tab
- [ ] User-facing strings are in English
- [ ] No new permissions / network calls (or justified above)
