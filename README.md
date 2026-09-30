# linuxify

Make **cmd** and **PowerShell** on Windows feel like a Linux terminal, in one command.

- **Syntax colors while you type**: in cmd, commands turn green when they exist and red when they don't; in PowerShell, commands, flags, strings and variables each get their own color
- **Suggestions from your history** in grey as you type (press → to accept), and ↑/↓ search history for what you've typed
- **`ls` like Linux**: columns, folders in blue, programs in green, plus `ll`, `la` and `lt` (tree)
- **Linux prompts**: `user@host:~/path $` with your git branch, or the Fedora/Ubuntu/Kali/Arch/oh-my-zsh style
- **Themes** you pick from a list with a live preview: Fedora, Ubuntu, Kali, Arch, Dracula, Nord, Gruvbox, Catppuccin, Tokyo Night
- **fastfetch** system info when a terminal opens, with the logo matching your theme

![Fedora theme](docs/fedora.png)

## Install

Paste this into PowerShell:

```powershell
irm https://raw.githubusercontent.com/teterw/linuxify/main/install.ps1 | iex
```

Then open a new terminal window. That's it.

The installer:

1. installs [Clink](https://github.com/chrisant996/clink), [eza](https://github.com/eza-community/eza) and [fastfetch](https://github.com/fastfetch-cli/fastfetch) with winget (skipped if you already have them)
2. updates PSReadLine for Windows PowerShell 5.1 if it's older than 2.3
3. copies linuxify to `%LOCALAPPDATA%\linuxify`
4. adds a 3-line block to your PowerShell profile (5.1 and 7). **Your existing profile is backed up first**, and nothing else in it is touched
5. hooks into cmd through Clink
6. sets your user's execution policy to `RemoteSigned` if it's `Restricted`, because otherwise PowerShell won't load profiles

Running it again updates linuxify and keeps your settings.

## Commands

| Command | What it does |
|---|---|
| `theme` | pick a theme with the arrow keys (the colors preview live) |
| `theme fedora` | switch theme directly |
| `theme list` | list themes |
| `ls` `ll` `la` `lt` | list / long list / include hidden / tree |
| `fastfetch` | system info |
| `linuxify fetch on\|off` | show fastfetch when a terminal opens |
| `linuxify icons on\|off` | file icons in `ls` (needs a [Nerd Font](https://www.nerdfonts.com/)) |
| `linuxify update` | update to the latest version |
| `linuxify uninstall` | remove linuxify |

All of these work in both cmd and PowerShell.

## Themes

| Theme | Prompt | fastfetch logo |
|---|---|---|
| `linuxify` (default) | `user@host:~/path (main) $`, keeps your terminal's colors | Windows |
| `ubuntu` | `user@host:~/path$` on aubergine | Ubuntu |
| `fedora` | `[user@host dir]$` | Fedora |
| `kali` | two-line `┌──(user㉿host)-[~]` | Kali |
| `arch` | `[user@host dir]$` | Arch |
| `dracula`, `gruvbox`, `tokyonight` | oh-my-zsh `➜  dir git:(main)` | Windows |
| `nord`, `catppuccin` | `user@host:~/path (main) $` | Windows |

| Kali | Dracula | Ubuntu (cmd) |
|---|---|---|
| ![Kali](docs/kali.png) | ![Dracula](docs/dracula.png) | ![Ubuntu](docs/ubuntu.png) |

Theme colors (background and palette) change live in **Windows Terminal**, the default terminal on Windows 11. In the old console window, you still get the prompt style and syntax colors, just not the background.

## Uninstall

```powershell
linuxify uninstall
```

or, if the `linuxify` command is gone:

```powershell
irm https://raw.githubusercontent.com/teterw/linuxify/main/uninstall.ps1 | iex
```

This removes the profile block, unhooks Clink, and puts back the Clink settings it changed. Clink, eza and fastfetch stay installed, and the uninstaller prints the `winget uninstall` commands if you want them gone too.

## Good to know

- In PowerShell, `ls` now prints text like Linux instead of returning objects. For scripts and pipelines such as `Get-ChildItem | Where-Object ...`, use `gci` or `dir`, which are unchanged.
- In cmd, `ls` is a doskey alias, so it works when typed but not inside `.bat` files or after a pipe.
- PowerShell can't color unknown commands red while you type (PSReadLine doesn't support it), but it does turn the `$` red on syntax errors. cmd does the red/green check through Clink.
- fastfetch doesn't run in VS Code's terminal, in scripts, or in a shell started from another shell.

## Credits

linuxify is a small layer that sets up and themes these tools:
[Clink](https://github.com/chrisant996/clink) ·
[PSReadLine](https://github.com/PowerShell/PSReadLine) ·
[eza](https://github.com/eza-community/eza) ·
[fastfetch](https://github.com/fastfetch-cli/fastfetch).
Theme colors are based on the Ubuntu/GNOME, Dracula, Nord, Gruvbox, Catppuccin and Tokyo Night palettes.

## License

MIT
