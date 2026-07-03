# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Lingua Recall** — a KDE Plasma 6 plasmoid for FSRS-6 spaced-repetition vocabulary review. Works alongside [Lingua Spanner](../lingua-spanner): Spanner saves translations to `linguaspanner.db`, Recall reads them for review scheduling.

- **Type:** Plasma/Applet (KPackageStructure)
- **Target:** Plasma 6.0+
- **Plugin ID:** `org.kde.lingua-recall`
- **License:** GPL-2.0-or-later
- **Database:** shares `~/.config/linguaspanner/linguaspanner.db` with lingua-spanner

## Architecture

Three-layer C++ design with zero-Qt algorithm core:

```
FsrsEngine (static lib fsrs_engine, pure C++, no Qt headers)
  ↑
ReviewDb  (static lib review_db, depends on Qt6::Sql + fsrs_engine)
  ↑
RecallHelper (QML_ELEMENT, part of LinguaRecallHelper QML plugin)
  ↑
QML UI (main.qml)
```

### FsrsEngine (`src/FsrsEngine.h/.cpp`)
FSRS-6 algorithm math — 21 trainable W parameters, all formulas (forgetting curve with trainable decay, stability/difficulty update, same-day review, interval calculation). Pure `std::array<double,21>`, no Qt dependency.

### ReviewDb (`src/ReviewDb.h/.cpp`)
SQLite CRUD layer managing three tables in `linguaspanner.db`:
- **review_cards** — per-translation FSRS state (S, D, state, due, reps, lapses)
- **review_log** — append-only review history (rating, S/D before/after, R, ms timestamp)
- **fsrs_params** — FSRS-6 global params singleton (21 W values, desired_retention, max_interval)

`reviewCard()` is the key integration point: loads card state → runs FsrsEngine::review() → updates card + inserts review_log → returns JSON.

### RecallHelper (`src/RecallHelper.h/.cpp`)
QML_ELEMENT façade exposing all card/review/param operations as Q_INVOKABLE methods. QML wrapper at `package/contents/ui/RecallHelperQml.qml`.

### QML UI (`package/contents/ui/main.qml`)
Three-tab review panel:
- **Review** — flashcard with tap-to-reveal + Again/Hard/Good/Easy buttons
- **New Words** — translations not yet in review_cards, with "Learn" button
- **Stats** — aggregate counts and card-by-state breakdown

## Directory Structure

```
lingua-recall/
├── CMakeLists.txt             # Static libs fsrs_engine + review_db → QML module
├── Makefile                   # Dev workflow
├── dev                        # Convenience: ./dev build|full|qml|restart
├── src/
│   ├── FsrsEngine.h/.cpp      # FSRS-6 algorithm engine (static lib)
│   ├── ReviewDb.h/.cpp        # SQLite CRUD (static lib)
│   └── RecallHelper.h/.cpp    # QML_ELEMENT façade
├── package/
│   ├── metadata.json
│   └── contents/
│       ├── config/
│       │   ├── main.xml       # KConfig XT (fontSizeBase)
│       │   └── config.qml
│       ├── lib/LinguaRecallHelper/  # Built .so + qmldir (CI-staged)
│       └── ui/
│           ├── main.qml
│           ├── ConfigGeneral.qml    # Font size + FSRS desired retention
│           └── RecallHelperQml.qml
├── tests/
│   ├── tst_FsrsEngine.cpp     # 23 algorithm unit tests (QTest)
│   ├── tst_ReviewDb.cpp       # 23 integration tests (in-memory SQLite)
│   └── tst_RecallHelper.qml   # 5 QML plugin tests
└── .github/workflows/build.yml
```

## Development

```sh
# First time
make configure

# Iterate
make build           # cmake --build + stage .so to package/
make full            # build + install + restart plasmashell
make qml             # install + restart (QML-only)
make launch          # plasmawindowed preview (no restart)
make install         # kpackagetool6 -i / -r + -i (first time or update)

# Tests
make check           # 46 C++ unit tests (FsrsEngine 23 + ReviewDb 23)
make qml-check       # 5 QML integration tests (requires build first)

./dev build|full|qml|restart|test   # Convenience wrapper
```

### Test details

```sh
# Run a single test suite
./build/tst_FsrsEngine
./build/tst_ReviewDb

# Run a single test function
./build/tst_ReviewDb "test_createCard_success"

# QML tests
qml6 -platform offscreen -I package/contents/lib tests/tst_RecallHelper.qml
```

### Debug

```sh
journalctl -f -o cat | grep -E "RecallHelper|ReviewDb|qml:"
QT_LOGGING_RULES="qt.qml.import*=true" plasmawindowed org.kde.lingua-recall
```

## FSRS-6 Parameters

Default 21 W values (optimized from the open-spaced-repetition/fsrs-rs reference):

```
[0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001,
 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483,
 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542]
```

Key: w[0..3]=S₀, w[4..5]=D₀, w[6..10]=success update, w[11..14]=failure update, w[15]=Hard penalty, w[16]=Easy bonus, w[17..19]=same-day, w[20]=forgetting curve decay.

## Commit workflow

1. `git status` → `git add -A`
2. Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`, `style:`, `refactor:`
3. Tag: `v<major>.<minor>.<patch>` — match `package/metadata.json` → `KPlugin.Version`

## Release workflow

1. Bump `package/metadata.json` → `KPlugin.Version`
2. Commit: `chore: bump metadata.json version to X.X.X`
3. Tag: `git tag vX.X.X HEAD`
4. Push: `git push --atomic origin main vX.X.X`
