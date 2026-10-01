# Chinese Typing Dictionary Backend

This repository builds a compact pinyin dictionary for the AutoHotkey Chinese typing practice application.

## Design

- GitHub Actions performs all dictionary-building work.
- The user's computer only runs AutoHotkey.
- No Python, Java, Node.js, npm, or other runtime is required on the user's computer.
- Character-level data provides fallback pronunciations.
- Phrase-level data is preferred for contextual/polyphonic pronunciation.
- `data/overrides/` is reserved for project-specific corrections.
- `generated/` contains files intended for the AHK client.

## Build

The workflow can be started manually from GitHub Actions, or on a schedule.

The generated dictionary is deliberately plain UTF-8 text so AHK v2 can consume it without a third-party JSON library.

## Generated files

- `generated/dictionary.tsv` — phrase/character pronunciation data
- `generated/manifest.json` — version, counts, hashes, and source information

The dictionary format is:

`type<TAB>text<TAB>pinyin`

where `type` is `P` for phrase or `C` for character.

Phrase entries may contain multiple pronunciation variants separated by ` || `.

## Upstream data

- `mozillazg/pinyin-data`
- `mozillazg/phrase-pinyin-data`

Both upstream repositories are MIT-licensed. Their data may include data derived from other sources with their own notices; see `THIRD_PARTY_LICENSES.md`.
