# Contributing

Thanks for helping with RDCMan Dark Theme. Bug reports, fixes, new themes and README improvements are all welcome.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting a bug

Search the [open issues](../../issues) first. If it's new, open one with the bug report form. It asks for:

- what you saw and what you expected,
- your Windows version (`winver`) and RDCMan version (Help, About),
- the theme you picked, or your custom colours,
- a trace, if the problem is flicker or a part of the window that keeps its old colour.

To record a trace, start the script with `-Trace` or press `T` in the menu, reproduce the problem, then close RDCMan. The file is `%TEMP%\rdcman-color-trace.txt`. It mostly records window classes, handles and paint messages. Read it before you attach it and remove anything you'd rather not share.

A screenshot helps a lot for colour problems. Blur any server names you don't want to share.

## Suggesting a feature or theme

Open an issue with the feature request form. For a new built-in theme, give the background, text and line colours as `#RRGGBB` and a screenshot of it running.

## Making a change

1. Fork the repo and create a branch from `main`.
2. Edit `Set-RdcmanTreeColor.ps1`. It has to run on Windows PowerShell 5.1, the version built into Windows, so don't use PowerShell 7 syntax such as `??`, `?.` or ternaries.
3. Check that the script still parses:

   ```powershell
   $e = $null
   [System.Management.Automation.Language.Parser]::ParseFile("$PWD\Set-RdcmanTreeColor.ps1", [ref]$null, [ref]$e) | Out-Null
   $e
   ```

   This must print nothing.
4. If you changed the C# part (the `$source` or `$outsideSource` here-strings), start RDCMan through the script once so it compiles, and fix any `Add-Type` error it shows.
5. Test on a real RDCMan: open a session, click between the server list and the session several times, open the menus and the "connect servers" popup, and try at least the Dark and Light grey themes.
6. Update `README.md` if you changed menu keys, parameters or option words, and add a line to `CHANGELOG.md`.
7. Open a pull request against `main` and fill in the template.

Keep each pull request to one fix or feature. `.ps1` and `.bat` files use CRLF line endings and `.gitattributes` keeps them that way, so leave line endings as they are.

## License

The project is MIT licensed. By contributing you agree that your work is released under the [MIT License](LICENSE) too. Only submit code you wrote yourself or have the right to share.
