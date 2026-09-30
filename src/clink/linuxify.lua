-- linuxify for cmd.exe (loaded by Clink): prompt, ls aliases, themes, fastfetch.
-- Settings live in config.txt next to this folder, written by cli.ps1.

local home = os.getenv("LOCALAPPDATA") .. "\\linuxify"
local cfgpath = home .. "\\config.txt"
local ps = 'powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' .. home .. '\\cli.ps1"'

-- Terminals started before eza/fastfetch were installed have a stale PATH
local links = os.getenv("LOCALAPPDATA") .. "\\Microsoft\\WinGet\\Links"
local envpath = os.getenv("PATH") or ""
if os.isdir(links) and not (";" .. envpath:lower() .. ";"):find(";" .. links:lower() .. ";", 1, true) then
    os.setenv("PATH", envpath .. ";" .. links)
end

local ESC = "\x1b"
local R = ESC .. "[0m"

local function read_config()
    local cfg = { theme = "linuxify", fetch = "on", icons = "off", style = "linuxify", logo = "", palette = "" }
    local raw = ""
    local f = io.open(cfgpath, "rb")
    if f then
        raw = f:read("*a") or ""
        f:close()
        for line in raw:gmatch("[^\r\n]+") do
            local k, v = line:match("^([%w_]+)=(.*)$")
            if k then cfg[k] = v end
        end
    end
    return cfg, raw
end

local function set_aliases(cfg)
    local base = "eza --group-directories-first --color=auto"
    if cfg.icons == "on" then base = base .. " --icons=auto" end
    os.setalias("ls", base .. " $*")
    os.setalias("ll", base .. " -l --git --time-style=long-iso $*")
    os.setalias("la", base .. " -la --git --time-style=long-iso $*")
    os.setalias("lt", base .. " --tree --level=2 $*")
    os.setalias("theme", ps .. " theme $*")
    os.setalias("linuxify", ps .. " $*")
end

local cfg, cfgraw = read_config()
set_aliases(cfg)

local function in_vscode()
    return os.getenv("TERM_PROGRAM") == "vscode"
end

local function palette_terminal()
    return (os.getenv("WT_SESSION") or os.getenv("WEZTERM_EXECUTABLE") or os.getenv("ConEmuANSI") == "ON")
        and not in_vscode()
end

local started = false
clink.onbeginedit(function()
    -- pick up changes made by `theme` / `linuxify` since the last prompt
    local newcfg, raw = read_config()
    if raw ~= cfgraw then
        cfg, cfgraw = newcfg, raw
        set_aliases(cfg)
    end

    if not started then
        started = true
        if cfg.palette ~= "" and palette_terminal() then
            clink.print(cfg.palette, NONL)
        end
        if cfg.fetch == "on" and not in_vscode() and not os.getenv("LINUXIFY_FETCHED") then
            os.setenv("LINUXIFY_FETCHED", "1")
            if cfg.logo ~= "" then
                os.execute("fastfetch --logo " .. cfg.logo .. " 2>nul")
            else
                os.execute("fastfetch 2>nul")
            end
        end
    end
end)

local function git_branch()
    local dir = os.getcwd()
    while dir and dir ~= "" do
        local git = dir .. "\\.git"
        local head
        if os.isdir(git) then
            head = git .. "\\HEAD"
        elseif os.isfile(git) then
            -- worktrees and submodules: .git is a file containing "gitdir: <path>"
            local f = io.open(git, "rb")
            if f then
                local gd = (f:read("*l") or ""):match("^gitdir:%s*(.-)%s*$")
                f:close()
                if gd then
                    if not gd:match("^%a:") and not gd:match("^[\\/]") then gd = dir .. "\\" .. gd end
                    head = gd .. "\\HEAD"
                end
            end
        end
        if head then
            local f = io.open(head, "rb")
            if f then
                local ref = (f:read("*l") or ""):gsub("%s+$", "")
                f:close()
                return ref:match("^ref: refs/heads/(.+)$") or ref:sub(1, 7)
            end
        end
        local parent = path.toparent(dir)
        if not parent or parent == dir then break end
        dir = parent
    end
end

local function cwd(leaf)
    local dir = os.getcwd()
    local userhome = (os.getenv("USERPROFILE") or ""):gsub("\\$", "")
    if dir:lower() == userhome:lower() then return "~" end
    if leaf then
        local name = path.getname(dir)
        if name == "" then return (dir:gsub("\\$", "")) end
        return name
    end
    if dir:lower():sub(1, #userhome + 1) == userhome:lower() .. "\\" then
        dir = "~" .. dir:sub(#userhome + 1)
    end
    return (dir:gsub("\\", "/"))
end

local lx_prompt = clink.promptfilter(5)
function lx_prompt:filter()
    local ok = os.geterrorlevel() == 0
    local user = os.getenv("USERNAME") or "user"
    local hostname = (os.getenv("COMPUTERNAME") or "windows"):lower()
    local style = cfg.style

    if style == "debian" then
        return ESC.."[1;32m"..user.."@"..hostname..R..":"..ESC.."[1;34m"..cwd()..R.."$ ", false
    elseif style == "bracket" then
        return "["..user.."@"..hostname.." "..cwd(true).."]$ ", false
    elseif style == "kali" then
        local g, b, w = ESC.."[32m", ESC.."[1;34m", ESC.."[1;37m"
        return g.."┌──("..b..user.."㉿"..hostname..R..g..")-["..w..cwd()..R..g.."]"..R.."\n"..g.."└─"..b.."$"..R.." ", false
    elseif style == "arrow" then
        local c = ok and ESC.."[1;32m" or ESC.."[1;31m"
        local s = c.."➜  "..ESC.."[36m"..cwd(true)..R
        local branch = git_branch()
        if branch then s = s.." "..ESC.."[1;34mgit:("..ESC.."[31m"..branch..ESC.."[1;34m)"..R end
        return s.." ", false
    else
        local s = ESC.."[92m"..user.."@"..hostname..R..":"..ESC.."[94m"..cwd()..R
        local branch = git_branch()
        if branch then s = s.." "..ESC.."[95m("..branch..")"..R end
        local sym = ok and ESC.."[92m$" or ESC.."[91m$"
        return s.." "..sym..R.." ", false
    end
end
