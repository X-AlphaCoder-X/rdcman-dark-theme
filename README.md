# RDCMan Dark Theme

A dark (or any colour you like) theme for Microsoft's **Remote Desktop Connection Manager**.

RDCMan only comes in bright white and has no theme setting. This script fixes that. It recolours the whole RDCMan window: the server tree, menu bar and dropdowns, right-click menus, title bar, borders, side and status panels, scrollbars, dialogs, and the empty area around a session that's smaller than the window.

The remote desktop itself is never touched. Only RDCMan's own window gets recoloured.

It's two files, a PowerShell script and a `.bat` launcher. There's nothing to install.

## Quick start

1. Download `rdc.bat` and `Set-RdcmanTreeColor.ps1` and put them **in the same folder**.
2. Close RDCMan if it's open.
3. Double-click **`rdc.bat`**.
4. Click **Yes** on the UAC prompt (the script restarts itself as Administrator).
5. Pick a theme from the menu.

RDCMan opens in the new colours.

```
  RDCMan window color
  -------------------
  RDCMan: C:\Tools\RDCMan\RDCMan.exe
  Administrator: yes

  1  Grey        back #4A4A4A   text #F0F0F0
  2  Dark        back #1E1E1E   text #DCDCDC
  3  Light grey  back #C8C8C8   text #111111
  4  Slate       back #3B4252   text #ECEFF4
  5  Midnight    back #14213D   text #E5E5E5
  6  Forest      back #1F2A22   text #DDEBDD
  7  Custom      (type your own hex colors)
  P  Change RDCMan location
  B  Background around a small session: On  (press B to switch)
  F  Freeze focus: ON  (press F to switch)
  T  Record a blink trace (this run only): OFF  (press T to switch)
  Q  Quit
```

| Key | What it does |
|---|---|
| `1` to `6` | Pick one of the built-in themes. `2` (Dark) is the classic dark mode. |
| `7` | Custom. Type your own background and text colour as `#RRGGBB`. |
| `P` | Tell it where RDCMan is (a folder or the `.exe`). It remembers your choice. |
| `B` | Toggle whether the empty space around a small session window gets coloured too. |
| `F` | Toggle freeze focus (on by default). While the server list gains or loses focus, its repainting is paused, so RDCMan's own colour resets can't make it flicker. A change applies the next time RDCMan starts. |
| `T` | Record a debug trace for this run (see [Troubleshooting](#troubleshooting)). |
| `Q` | Quit. |

## Things to know

- **Start RDCMan through the script from now on.** The menu bar and panels are drawn inside RDCMan, so they can't be recoloured from outside. The script starts RDCMan itself and recolours it from the inside.
- **Keep the PowerShell window open.** Closing it closes RDCMan too. To hide that window, see [Hidden shortcut](#hidden-shortcut).
- **Finding RDCMan.** The script looks in the folder you set with `P`, then `C:\Tools\RDCMan`, then any RDCMan that's already running, then the script's own folder, `Downloads`, `Desktop`, and `Program Files\Microsoft\Remote Desktop Connection Manager`. If it can't find RDCMan, it asks.
- **The server list keeps its classic rows.** By default only its colours change, and its scrollbar is dark. The animated dark theme made the selected row fade through the background colour every time focus moved, which looked like a blink. Add `darktree` to the options file (see [Troubleshooting](#troubleshooting)) if you want it back.
- **Nothing is installed.** Your settings live in a few small text files in `%APPDATA%` (`rdcman-color-*.txt`). Delete them to reset.

## Command-line use

You can skip the menu:

```powershell
.\Set-RdcmanTreeColor.ps1                        # menu
.\Set-RdcmanTreeColor.ps1 -Choice 2              # straight to theme 2 (Dark)
.\Set-RdcmanTreeColor.ps1 -BackColor '#3B3F46'   # your own background colour
.\Set-RdcmanTreeColor.ps1 -BackColor '#202020' -TextColor '#E0E0E0'
.\Set-RdcmanTreeColor.ps1 -SessionBackground Off  # don't colour around small sessions
.\Set-RdcmanTreeColor.ps1 -RdcmanPath 'C:\Tools\RDCMan'
.\Set-RdcmanTreeColor.ps1 -Trace                 # record a debug trace
```

`rdc.bat` passes any arguments through, so `rdc.bat -Choice 2` works too.

### Hidden shortcut

To get a desktop shortcut that opens RDCMan dark without a console window, create a shortcut with this target (change the path):

```
powershell.exe -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\path\to\Set-RdcmanTreeColor.ps1" -Choice 2
```

Closing RDCMan ends it.

## Troubleshooting

**"Running scripts is disabled on this system".** Use `rdc.bat`. It runs the script with `-ExecutionPolicy Bypass` for that one run and doesn't change your system policy. If you downloaded the files, you can also right-click them, open **Properties**, and tick **Unblock**.

**"RDCMan: NOT FOUND".** Press `P` and paste the folder that contains `RDCMan.exe`.

**The server list flickers or blinks when you click between it and a session.**

Freeze focus (`F` in the menu) is on by default and stops most of this. If you still see it:

1. Start with `-Trace`, or press `T` in the menu.
2. Click the session, then the server list, then the session again, a few times.
3. Close RDCMan.
4. The trace is saved to `%TEMP%\rdcman-color-trace.txt`. Attach it to an [issue](../../issues).

There are also a few optional tweaks you can try. Create `%APPDATA%\rdcman-color-options.txt` and put any of these words in it, separated by spaces or new lines:

| Word | Effect |
|---|---|
| `stopanim` | Cut off the selection/hover animation on the server list |
| `nodouble` | Turn off double buffering on the server list |
| `keeptreefill` | Use the older way of filling the list background |
| `keephot` | Leave hot-tracking alone |
| `keepfade` | Leave the expander fade alone |
| `selectcolors` | Swap the system selected-row colours for theme colours |
| `darktree` | Give the server list the animated dark theme back (dark scrollbar, but the selected row blinks on focus changes) |
| `notheme` | Draw the server list rows the classic way (the default). The scrollbar stays dark unless `lightscroll` is also set |
| `lightscroll` | Leave the server list scrollbar light |
| `lightheader` | Leave the column header bar of the "connect servers" popup white |
| `darklist` | Give the popup's list the animated dark theme instead of classic rows |
| `handsoff` | Don't turn on double buffering for the server list |
| `freezefocus` | Pause the server list's painting while it gains or loses focus. The `F` menu setting wins over this word |
| `nocolorskip` | Pass every tree colour message on, including ones that change nothing |
| `sessionguard` | Also paint the area behind each session in the theme colour. Off by default, because it paints at the moment focus moves into a session |

**Want the white look back?** Just start RDCMan the normal way, without the script. Nothing is changed permanently.

## Requirements

- Windows 10/11 or Windows Server 2016+
- Windows PowerShell 5.1 (built into Windows)
- [RDCMan](https://learn.microsoft.com/en-us/sysinternals/downloads/rdcman) 2.x from Sysinternals
- Administrator rights (the script asks for them via UAC)

## Contributing

Bug reports, fixes and new themes are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to record a trace and test a change, and [CHANGELOG.md](CHANGELOG.md) for what changed in each version. Report security problems privately, as [SECURITY.md](SECURITY.md) describes.

## License

[MIT](LICENSE). Not affiliated with Microsoft. RDCMan is a Microsoft Sysinternals tool.
