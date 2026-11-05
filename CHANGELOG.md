# Changelog

Versions follow [Semantic Versioning](https://semver.org/). Each version is a [GitHub release](../../releases) with a zip of the files.

## 1.1.1 - 2026-11-05

### Fixed

- RDCMan could now and then show an error that ends in "Dispose() cannot be called while doing CreateHandle()", for example when opening a server's Properties. The script recoloured windows, took over their painting and redrew their frame the moment they appeared, even while a dialog was still being built. That work now waits until the window's form is fully created. Colours are still set at once, so windows look the same and change colour as fast as before.

### Added

- A crash note. If that error ever happens again, the script writes the last steps it took and the call stack to `%TEMP%\rdcman-color-crash.txt`. It records window types only, never window titles, because titles can contain server names. The first note of each RDCMan run replaces the file, and a run writes at most 5 notes. The error itself is left alone, so RDCMan behaves as before.

## 1.1.0 - 2026-11-05

### Changed

- Better theme colours. The column header bar of the "connect servers" popup is now drawn in the theme colours. It used to stay white. The popup's list and the server list keep RDCMan's classic rows in your colours, with dark scrollbars.
- The selected server keeps its highlight while focus moves between the server list and a session. The colour is now picked from the row's own state, so it no longer flashes to the list background for a moment.

### Fixed

- Flickering in the server list. Freeze focus pauses the list's repainting while it gains or loses focus, so RDCMan's own colour resets can't make it blink, and then repaints the selected row once. It's on by default. Press `F` in the menu to switch it. The choice is remembered and applies the next time RDCMan starts.
- The animated dark theme on the server list made the selected row fade through the background colour on every focus change. The list now uses classic rows by default. Add `darktree` to `%APPDATA%\rdcman-color-options.txt` to get the animated theme back.

### Added

- Better debugging. The trace (`-Trace` or `T` in the menu) now records when the popup's header bar is taken over and when the server list gets dark scrollbars with classic rows, and the script prints whether freeze focus is on when it starts RDCMan.
- New words for `rdcman-color-options.txt`: `darktree`, `notheme`, `lightscroll`, `lightheader`, `darklist`, `handsoff` and `freezefocus`. The README lists what each one does.

## 1.0.0 - 2026-10-24

First release: the theme script, the `rdc.bat` launcher and six built-in themes plus custom colours.
