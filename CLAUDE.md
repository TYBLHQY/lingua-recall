# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Lingua Recall** — a KDE Plasma 6 plasmoid (applet) framework scaffold, architected after [Lingua Spanner](../lingua-spanner). Currently a skeleton with no business logic; ready for spaced-repetition / recall assistant feature development.

- **Type:** Plasma/Applet (KPackageStructure)
- **Target:** Plasma 6.0+
- **Plugin ID:** `org.kde.lingua-recall`
- **License:** GPL-2.0+ (tbd)

## Directory Structure

```
lingua-recall/
├── CLAUDE.md                  # This file — AI development guide
├── CMakeLists.txt             # C++ build (RecallHelper QML module)
├── Makefile                   # Dev workflow: build, install, test, restart
├── dev                        # Convenience script: ./dev build|full|qml|restart
├── .github/workflows/
│   └── build.yml              # CI: Qt 6.7 + cmake → package → GitHub Release
├── package/
│   ├── metadata.json          # Plugin ID: org.kde.lingua-recall, v0.1.0
│   ├── translate/.gitkeep     # i18n translation files (future)
│   └── contents/
│       ├── config/
│       │   ├── main.xml       # KConfig XT schema (fontSizeBase placeholder)
│       │   └── config.qml     # Shell that loads ConfigGeneral.qml
│       ├── lib/LinguaRecallHelper/  # C++ QML module (.so + qmldir, staged by build)
│       └── ui/
│           ├── main.qml              # PlasmoidItem skeleton
│           ├── ConfigGeneral.qml     # Placeholder KCM settings page
│           └── RecallHelperQml.qml   # QML wrapper for C++ RecallHelper
├── src/
│   ├── RecallHelper.h         # QML_ELEMENT C++ QObject (scaffold)
│   ├── RecallHelper.cpp       # Stub with hello() verification
│   └── .gitkeep
├── tests/
│   ├── tst_RecallHelper.qml   # Qt Quick Test for RecallHelper
│   └── .gitkeep
└── .gitignore
```

## Architecture

### C++ QML Module (`LinguaRecallHelper`)

A single QML_ELEMENT C++ class (`RecallHelper : QObject`) exposed via `qt_add_qml_module`. Currently a stub containing `Q_INVOKABLE QString hello()` for module-load verification. Extend with domain-specific `Q_INVOKABLE` methods, properties, and signals as business logic develops.

Relevant files:
- `src/RecallHelper.h` / `src/RecallHelper.cpp` — C++ source
- `package/contents/ui/RecallHelperQml.qml` — QML wrapper that instantiates the helper

### Config pipeline

`main.xml` (KConfig XT) → `config.qml` (shell) → `ConfigGeneral.qml` (actual widget). Currently only `fontSizeBase` is defined. Add KConfig XT entries in `main.xml` and corresponding UI in `ConfigGeneral.qml` as features grow.

### Activation

The `PlasmoidItem` in `main.qml` provides:
- **compactRepresentation**: taskbar icon (`adjustcoloreffects`)
- **fullRepresentation**: popup panel with header, content area, status bar

Customize the click/shortcut activation pattern from `main.qml` (mirror lingua-spanner's `handlePanelOpened()` → selection/freshness pattern if clipboard interaction is needed, or replace entirely for the recall domain).

### Placeholder areas (ready for filling)

| Location | Purpose | Status |
|----------|---------|--------|
| `package/contents/ui/main.qml` | PlasmoidItem — main UI | Skeleton panel |
| `package/contents/ui/ConfigGeneral.qml` | KCM settings | Skeleton with font size |
| `package/contents/config/main.xml` | KConfig XT schema | Single entry (fontSizeBase) |
| `src/RecallHelper.h/.cpp` | C++ helpers | Stub with hello() |
| `tests/tst_RecallHelper.qml` | Unit tests | Stub test |
| `package/translate/` | i18n files | Empty |

## Development

```sh
# Info
make status          # git log, plasmoid install status, module file info
make configure       # cmake configure (first time after clone)

# Iterate
make build           # cmake --build + stage .so to package (C++ changes)
make qml             # kpackagetool6 -u + restart (QML-only changes)
make full            # full deploy (build + install + restart)
make test            # install + plasmawindowed preview (no shell restart)
make restart         # kquitapp6 + plasmashell --replace

# Tests
qml6 -I package/contents/lib tests/tst_RecallHelper.qml   # Unit tests

# Debug
journalctl -f -o cat | grep -E "RecallHelper|qml:"       # Plasmoid logs
```

## Commit workflow

1. Verify git status is clean (`git status`)
2. Stage only relevant files with `git add -A`
3. Use conventional commits: `feat:`, `fix:`, `docs:`, `chore:`, `style:`, `refactor:`
4. For feature/fix commits with significant changes, include a body with bullet points
5. Tag format: `v<major>.<minor>.<patch>` — matched to `package/metadata.json` → `KPlugin.Version`

## Update / release workflow

1. Bump `package/metadata.json` → `KPlugin.Version` to the new version string
2. Commit: `chore: bump metadata.json version to X.X.X`
3. Tag: `git tag vX.X.X HEAD`
4. Push with `git push --atomic origin main vX.X.X`
