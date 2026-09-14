# Codex Day — archived

This project was closed at the owner's request on 14 September 2026. Development has ended. Closure does not mean that every requested feature was successfully delivered.

Codex Day explored an in-app calendar and editable daily to-do board, opened from a Day button in the Codex toolbar. An isolated local helper used Apple EventKit, while a local scheduled job extracted explicit action items from locally stored Codex conversations without model calls.

## Final status

- Implemented: calendar and to-do cards, editing, light and dark card appearances, a background helper, offline midnight extraction, a dedicated launcher and reversible runtime installation.
- Partially verified: local task editing, extraction rules and renderer target validation.
- Unresolved: reliable desktop-visible frosted glass across the whole native window; overlapping panels and toolbar integration in real Codex windows; the reported lack of response when opening the original application.
- Not fully verified: Apple Calendar and Reminders synchronisation with the owner's live accounts.

The renderer extension is not an official custom-toolbar API. A plugin manifest alone cannot provide this interface. Do not treat this archived prototype as a supported or production-ready extension.

## Repository contents

`codex-day/` contains the plugin manifest, renderer assets, Swift helper and launcher, offline extractor and operational skill. `scripts/` contains build, installation and removal tools. `tests/` contains the existing checks and a synthetic interface fixture.

The retained source requires macOS 14 or later, Swift command-line tools, Python 3 and the official application's bundled Node runtime. No runtime npm or pip packages are required.

Historical build and removal commands:

```sh
./scripts/build.sh
python3 scripts/install.py
python3 scripts/uninstall.py
```

The uninstaller preserves personal to-dos and Apple Reminders. Review the source and compatibility before attempting to reinstall this archived prototype.

## Records and privacy

See [ARCHIVE.md](ARCHIVE.md) for the final engineering record. Personal conversations, screenshots, calendar entries, extracted suggestions, credentials and local application settings are not included in this repository. Git history retains the earlier implementation states, including historical Chinese-language documentation; the final documentation is in British English.

## Acknowledgements

Design and integration research referred to [Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin), [Apple Materials](https://developer.apple.com/design/human-interface-guidelines/materials) and [LiquidGlass for Obsidian](https://github.com/GavinKalvin/LiquidGlass_plugin). No Obsidian native binary was loaded into Codex. Attribution is retained in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
