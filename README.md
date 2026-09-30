# linuxify

Make **cmd** and **PowerShell** on Windows feel like a Linux terminal, in one command.

- **Syntax colors while you type**: in cmd, commands turn green when they exist and red when they don't; in PowerShell, commands, flags, strings and variables each get their own color
- **Suggestions from your history** in grey as you type. Press **Ctrl+F** (or →) to accept, and ↑/↓ to search history for what you've typed
- **`ls` like Linux**: columns, folders in blue, programs in green, plus `ll`, `la` and `lt` (tree)
- **`theme`**: one menu to pick your **colors** (24 themes), **prompt** (10 styles) and **fastfetch logo** (32 logos), each with a live preview
- **fastfetch** system info when a terminal opens

![Fedora colors with the Fedora logo](docs/fedora.png)

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

Running it again (or `linuxify update`) updates linuxify and keeps your settings.

## Themes

Run `theme` to open the menu:

![theme menu](docs/menu.png)

Colors, prompt and logo are separate, so you can mix them freely, for example Dracula colors with the Kali prompt and the Arch logo.

| Colors: preview changes live | Logo: previewed beside the list |
|---|---|
| ![colors picker](docs/colors.png) | ![logo picker](docs/logos.png) |

In the pickers: ↑/↓ to move, type a letter to jump, Enter to choose, Esc to go back.

**Colors (24):** Terminal default, Ubuntu, Fedora, Kali, Arch, Dracula, Nord, Gruvbox, Catppuccin Mocha, Tokyo Night, One Dark, Monokai, Solarized Dark, Rose Pine, Everforest, Kanagawa, GitHub Dark, Night Owl, Ayu Dark, Cobalt2, Synthwave '84, Hacker Green, and two light themes: Catppuccin Latte and GitHub Light.

**Prompts (10):**

| Prompt | Looks like |
|---|---|
| Linuxify (default) | `user@host:~/path (main) $` |
| Ubuntu / Debian | `user@host:~/path$` |
| Fedora / Arch | `[user@host dir]$` |
| Kali | `┌──(user㉿host)-[~]` + `└─$` |
| Parrot OS | `┌─[user@host]─[~]` + `└──╼ $` |
| oh-my-zsh | `➜  dir git:(main)` |
| fish | `user@host ~/D/github>` |
| Pure | `~/path main` + `❯` |
| Minimal | `dir ❯` |
| macOS | `user@host dir %` |

**fastfetch logos (32):** Windows (default), Windows 11 small, Windows 10, Windows 7, Windows 95, Linux (Tux), Ubuntu, Fedora, Debian, Arch, Kali, Linux Mint, Manjaro, Pop!_OS, EndeavourOS, CachyOS, Garuda, openSUSE, Gentoo, NixOS, Void, Alpine, Zorin, elementary OS, Parrot OS, Raspberry Pi OS, SteamOS, macOS, FreeBSD, Android, TempleOS, or no logo.

| Kali prompt + Kali colors | oh-my-zsh prompt + Dracula | Ubuntu in cmd |
|---|---|---|
| ![Kali](docs/kali.png) | ![Dracula](docs/dracula.png) | ![Ubuntu](docs/ubuntu.png) |

Theme colors (background and palette) change live in **Windows Terminal**, the default terminal on Windows 11. In the old console window, you still get the prompts and syntax colors, just not the background.

## Commands

| Command | What it does |
|---|---|
| `theme` | menu: colors, prompt, fastfetch logo, fastfetch at startup, icons |
| `theme colors` / `theme colors nord` | pick colors, or set them directly |
| `theme prompt` / `theme prompt kali` | pick a prompt style, or set it directly |
| `theme logo` / `theme logo arch` | pick the fastfetch logo, or set it directly |
| `theme list` | list every color theme, prompt and logo |
| `ls` `ll` `la` `lt` | list / long list / include hidden / tree |
| `fastfetch` | system info with your chosen logo |
| `linuxify fetch on\|off` | show fastfetch when a terminal opens |
| `linuxify icons on\|off` | file icons in `ls` (needs a [Nerd Font](https://www.nerdfonts.com/)) |
| `linuxify update` | update to the latest version |
| `linuxify uninstall` | remove linuxify |

All of these work in both cmd and PowerShell.

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
- PowerShell can't color unknown commands red while you type (PSReadLine doesn't support it), but it does turn the end of the prompt red on syntax errors. cmd does the red/green check through Clink.
- fastfetch doesn't run in VS Code's terminal, in scripts, or in a shell started from another shell.
- Upgrading from 1.0 keeps your colors and prompt. The logo resets to Windows, since logos are now their own setting.

## Credits

linuxify is a small layer that sets up and themes these tools:
[Clink](https://github.com/chrisant996/clink) ·
[PSReadLine](https://github.com/PowerShell/PSReadLine) ·
[eza](https://github.com/eza-community/eza) ·
[fastfetch](https://github.com/fastfetch-cli/fastfetch).
Color themes are based on the Ubuntu/GNOME, Dracula, Nord, Gruvbox, Catppuccin, Tokyo Night, One Dark, Monokai, Solarized, Rosé Pine, Everforest, Kanagawa, GitHub, Night Owl, Ayu, Cobalt2 and Synthwave '84 palettes.

## License

MIT
