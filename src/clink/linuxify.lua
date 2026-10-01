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

-- Ctrl+F accepts the grey suggestion (Right arrow and End still work too)
rl.setbinding([["\C-f"]], "clink-insert-suggested-line", "emacs")

local ESC = "\x1b"
local R = ESC .. "[0m"

local function read_config()
    local cfg = { colors = "default", prompt = "linuxify", fetch = "on", icons = "off", logo_id = "", palette = "" }
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
    if cfg.style and not raw:find("\nprompt=") and not raw:find("^prompt=") then cfg.prompt = cfg.style end
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
    -- fastfetch uses the chosen logo (a --logo you type yourself comes later and wins)
    if cfg.logo_id ~= "" then
        os.setalias("fastfetch", 'fastfetch.exe --logo "' .. cfg.logo_id .. '" $*')
    else
        os.setalias("fastfetch", "fastfetch.exe $*")
    end
end

local cfg, cfgraw = read_config()
set_aliases(cfg)

--------------------------------------------------------------------------------
-- Linux commands and shell habits for cmd: cd -, .., mkcd, pwd, export, which,
-- open, mkdir -p, sudo, plus grep/head/tail/wc/touch/df/free/uptime/rm/killall
-- (run by lx.ps1). Each command in the typed line, split at |, &, && and ||,
-- is rewritten before cmd runs it.

local lx = 'powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' .. home .. '\\lx.ps1"'
local helper_cmds = { touch = true, head = true, tail = true, grep = true, wc = true, df = true,
                      free = true, uptime = true, rm = true, killall = true }
local builtins = { dir = true, del = true, erase = true, copy = true, move = true, ren = true, rename = true,
                   md = true, mkdir = true, rd = true, rmdir = true, type = true, echo = true, set = true,
                   cd = true, chdir = true, mklink = true, start = true, cls = true, ver = true, vol = true,
                   assoc = true, ftype = true, path = true, pushd = true, popd = true, title = true,
                   color = true, date = true, time = true, ["for"] = true, ["if"] = true, call = true }

-- Real GNU tools on PATH (Git, MSYS2...) win over linuxify's versions
local path_cache = {}
local function on_path(name)
    if path_cache[name] == nil then
        path_cache[name] = false
        for dir in (os.getenv("PATH") or ""):gmatch("[^;]+") do
            for _, ext in ipairs({ ".exe", ".cmd", ".bat" }) do
                if os.isfile(dir .. "\\" .. name .. ext) then path_cache[name] = true; return true end
            end
        end
    end
    return path_cache[name]
end

-- Windows 11 sudo mode: 0 off, 1 new window, 2 input closed, 3 inline
local sudo_mode
local function get_sudo_mode()
    if sudo_mode == nil then
        sudo_mode = 0
        if os.isfile((os.getenv("windir") or "C:\\Windows") .. "\\System32\\sudo.exe") then
            local p = io.popen('reg query "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Sudo" /v Enabled 2>nul')
            if p then
                local out = p:read("*a") or ""
                p:close()
                sudo_mode = tonumber(out:match("Enabled%s+REG_DWORD%s+0x(%x+)") or "0", 16) or 0
            end
        end
    end
    return sudo_mode
end

-- "a b" c  ->  { 'a b', 'c' }
local function split_args(s)
    local args, cur, inq, has = {}, "", false, false
    for ch in s:gmatch(".") do
        if ch == '"' then
            inq = not inq; has = true
        elseif ch:match("%s") and not inq then
            if has or cur ~= "" then table.insert(args, cur) end
            cur, has = "", false
        else
            cur = cur .. ch
        end
    end
    if has or cur ~= "" then table.insert(args, cur) end
    return args
end

-- Splits a line at unquoted & | && || ( ), keeping the separators so it can be put back together.
local function split_line(line)
    local parts, cur, inq, i = {}, "", false, 1
    while i <= #line do
        local ch = line:sub(i, i)
        if ch == '"' then
            inq = not inq; cur = cur .. ch
        elseif ch == "^" and not inq then
            cur = cur .. line:sub(i, i + 1); i = i + 1
        elseif not inq and (ch == "&" or ch == "|" or ch == "(" or ch == ")") then
            local sep = ch
            if (ch == "&" or ch == "|") and line:sub(i + 1, i + 1) == ch then sep = ch .. ch; i = i + 1 end
            table.insert(parts, cur); table.insert(parts, sep); cur = ""
        else
            cur = cur .. ch
        end
        i = i + 1
    end
    table.insert(parts, cur)
    return parts
end

local last_dir, prev_dir

local rewrite
local function rewrite_command(w, rest, args)
    if w == "cd" or w == "chdir" then
        if args == "" then return 'cd /d "%USERPROFILE%"' end
        if args == "-" then
            if not prev_dir then return "echo cd: OLDPWD not set" end
            return 'cd /d "' .. prev_dir .. '" && echo ' .. prev_dir
        end
        if args:sub(1, 1) == "/" then return nil end
        if args:sub(1, 1) == "~" then return 'cd /d "%USERPROFILE%' .. args:sub(2):gsub('"', ""):gsub("/", "\\") .. '"' end
        return "cd /d " .. args
    end
    if w:match("^%.%.+$") and args == "" then
        return "cd " .. ("..\\"):rep(#w - 1):sub(1, -2)
    end
    if w == "mkcd" then
        local a = split_args(args)
        if #a ~= 1 then return "echo usage: mkcd DIR" end
        local d = a[1]:gsub("/", "\\")
        return '(if not exist "' .. d .. '\\" mkdir "' .. d .. '") && cd /d "' .. d .. '"'
    end
    if w == "pwd" and args == "" then return "cd" end
    if (w == "export" or w == "env") and args == "" then return "set" end
    if w == "export" or w == "unset" then
        local cmds = {}
        for _, a in ipairs(split_args(args)) do
            if w == "unset" then
                table.insert(cmds, 'set "' .. a .. '="')
            else
                local name, value = a:match("^([%w_]+)=(.*)$")
                if name then table.insert(cmds, 'set "' .. name .. "=" .. value .. '"') end
            end
        end
        if #cmds == 0 then return nil end
        return table.concat(cmds, " & ")
    end
    if w == "which" and not on_path("which") then
        local names = {}
        for _, a in ipairs(split_args(args)) do
            if a:sub(1, 1) ~= "-" then table.insert(names, a) end
        end
        return "where " .. table.concat(names, " ")
    end
    if (w == "open" or w == "xdg-open") and args ~= "" then
        local cmds = {}
        for _, a in ipairs(split_args(args)) do table.insert(cmds, 'start "" "' .. a .. '"') end
        return table.concat(cmds, " & ")
    end
    if w == "mkdir" or w == "md" then
        for _, a in ipairs(split_args(args)) do
            if a:sub(1, 1) == "-" or a:find("/", 1, true) then return lx .. " mkdir" .. rest end
        end
        return nil
    end
    if w == "sudo" and args ~= "" then
        local mode = get_sudo_mode()
        local inner = rewrite(args)
        if mode == 0 then return lx .. " sudo " .. args end
        local first = (inner:match("^%s*(%S+)") or ""):lower()
        if mode == 1 then return "sudo cmd /k " .. inner end   -- new window: keep it open
        if builtins[first] then return "sudo cmd /c " .. inner end
        return "sudo " .. inner
    end
    if helper_cmds[w] and not on_path(w) then
        return lx .. " " .. w .. rest
    end
    return nil
end

-- Rewrites one command (no separators); returns it unchanged if it isn't ours.
rewrite = function(seg)
    local lead, body, trail = seg:match("^(%s*)(.-)(%s*)$")
    if body == "" then return seg end
    local word, rest = body:match("^(%S+)(.*)$")
    local out = rewrite_command(word:lower(), rest, rest:match("^%s*(.-)%s*$"))
    if not out then return seg end
    return lead .. out .. trail
end

-- Dry run for testing: LINUXIFY_REWRITE_TEST=<file of lines> writes what each line would become.
local testfile = os.getenv("LINUXIFY_REWRITE_TEST")
if testfile then
    local src, out = io.open(testfile, "rb"), io.open(testfile .. ".out", "wb")
    if src and out then
        prev_dir = "C:\\previous\\dir"
        for line in src:lines() do
            local parts = split_line((line:gsub("\r$", "")))
            for i = 1, #parts, 2 do parts[i] = rewrite(parts[i]) end
            out:write(line:gsub("\r$", ""), "\n  => ", table.concat(parts), "\n")
        end
        src:close(); out:close()
    end
end

-- `linuxify restart`: reload these scripts, then start up again like a new terminal (see onbeginedit)
local function is_restart(line)
    local a, b = line:match("^%s*(%S+)%s+(%S+)%s*$")
    if not a or a:lower() ~= "linuxify" then return false end
    b = b:lower()
    return b == "restart" or b == "reload"
end

clink.onfilterinput(function(line)
    if is_restart(line) then
        clink.reload()
        return 'set "LINUXIFY_FETCHED=" & cls'
    end
    local parts = split_line(line)
    local changed = false
    for i = 1, #parts, 2 do
        local new = rewrite(parts[i])
        if new ~= parts[i] then parts[i] = new; changed = true end
    end
    if changed then return table.concat(parts) end
end)

local function in_vscode()
    return os.getenv("TERM_PROGRAM") == "vscode"
end

local function palette_terminal()
    return (os.getenv("WT_SESSION") or os.getenv("WEZTERM_EXECUTABLE") or os.getenv("ConEmuANSI") == "ON")
        and not in_vscode()
end

-- Windows Terminal resets colors set by escape codes whenever it reloads settings.json (after a
-- window option, or a change in its own Settings page). Each prompt checks, and while the file
-- changed shortly before the theme was last applied, applies it again.
local term_files = {}
if os.getenv("WT_SESSION") then
    local la = os.getenv("LOCALAPPDATA") or ""
    for _, p in ipairs({ "Microsoft.WindowsTerminal_8wekyb3d8bbwe", "Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe",
                         "Microsoft.WindowsTerminalCanary_8wekyb3d8bbwe" }) do
        local f = la .. "\\Packages\\" .. p .. "\\LocalState\\settings.json"
        if os.isfile(f) then table.insert(term_files, f) end
    end
    local f = la .. "\\Microsoft\\Windows Terminal\\settings.json"
    if os.isfile(f) then table.insert(term_files, f) end
end
local palette_at = 0

local function update_palette()
    if cfg.palette == "" or #term_files == 0 or not palette_terminal() then return end
    local newest = 0
    for _, f in ipairs(term_files) do
        local t = os.globfiles(f, 2)
        if t and t[1] and t[1].mtime and t[1].mtime > newest then newest = t[1].mtime end
    end
    -- file times may be whole seconds, so allow two
    if newest > palette_at - 2 then
        clink.print(cfg.palette, NONL)
        palette_at = os.time()
    end
end

local started = false
clink.onbeginedit(function()
    -- remember the previous folder for `cd -`, however the folder changed
    local here = os.getcwd()
    if last_dir and here ~= last_dir then prev_dir = last_dir end
    last_dir = here

    -- pick up changes made by `theme` / `linuxify` since the last prompt
    local newcfg, raw = read_config()
    if raw ~= cfgraw then
        cfg, cfgraw = newcfg, raw
        set_aliases(cfg)
    end

    if not started then
        started = true
        if palette_terminal() then
            -- reset first, in case `linuxify restart` switched back to the terminal's own colors
            clink.print(ESC.."]104"..ESC.."\\"..ESC.."]110"..ESC.."\\"..ESC.."]111"..ESC.."\\"..ESC.."]112"..ESC.."\\"..cfg.palette, NONL)
            palette_at = os.time()
        end
        if cfg.fetch == "on" and not in_vscode() and not os.getenv("LINUXIFY_FETCHED") then
            os.setenv("LINUXIFY_FETCHED", "1")
            if cfg.logo_id ~= "" then
                os.execute('fastfetch --logo "' .. cfg.logo_id .. '" 2>nul')
            else
                os.execute("fastfetch 2>nul")
            end
        end
    else
        update_palette()
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

-- Current directory as ~/linux/style/path, just its last part ("leaf"),
-- or fish-style with parent folders shortened to one letter ("short").
local function cwd(mode)
    local dir = os.getcwd()
    local userhome = (os.getenv("USERPROFILE") or ""):gsub("\\$", "")
    if dir:lower() == userhome:lower() then return "~" end
    if mode == "leaf" then
        local name = path.getname(dir)
        if name == "" then return (dir:gsub("\\$", "")) end
        return name
    end
    if dir:lower():sub(1, #userhome + 1) == userhome:lower() .. "\\" then
        dir = "~" .. dir:sub(#userhome + 1)
    end
    dir = dir:gsub("\\$", ""):gsub("\\", "/")
    if mode == "short" then
        local parts = {}
        for part in dir:gmatch("[^/]+") do table.insert(parts, part) end
        for i = 1, #parts - 1 do
            if #parts[i] > 1 and not parts[i]:match(":$") then
                parts[i] = parts[i]:sub(1, parts[i]:sub(1, 1) == "." and 2 or 1)
            end
        end
        dir = table.concat(parts, "/")
    end
    return dir
end

local lx_prompt = clink.promptfilter(5)
function lx_prompt:filter()
    local ok = os.geterrorlevel() == 0
    local user = os.getenv("USERNAME") or "user"
    local hostname = (os.getenv("COMPUTERNAME") or "windows"):lower()
    local style = cfg.prompt

    if style == "debian" then
        return ESC.."[1;32m"..user.."@"..hostname..R..":"..ESC.."[1;34m"..cwd()..R.."$ ", false
    elseif style == "bracket" then
        return "["..user.."@"..hostname.." "..cwd("leaf").."]$ ", false
    elseif style == "kali" then
        local g, b, w = ESC.."[32m", ESC.."[1;34m", ESC.."[1;37m"
        return g.."┌──("..b..user.."㉿"..hostname..R..g..")-["..w..cwd()..R..g.."]"..R.."\n"..g.."└─"..b.."$"..R.." ", false
    elseif style == "parrot" then
        local red = ESC.."[0;31m"
        local x = ok and "" or "["..ESC.."[1;93m✗"..red.."]─"
        return red.."┌─"..x.."["..R..user..ESC.."[1;33m@"..ESC.."[1;96m"..hostname..red.."]─["..ESC.."[0;32m"..cwd()..red.."]"..R
            .."\n"..red.."└──╼ "..ESC.."[1;33m$"..R.." ", false
    elseif style == "arrow" then
        local c = ok and ESC.."[1;32m" or ESC.."[1;31m"
        local s = c.."➜  "..ESC.."[36m"..cwd("leaf")..R
        local branch = git_branch()
        if branch then s = s.." "..ESC.."[1;34mgit:("..ESC.."[31m"..branch..ESC.."[1;34m)"..R end
        return s.." ", false
    elseif style == "fish" then
        return ESC.."[32m"..user..R.."@"..hostname.." "..ESC.."[32m"..cwd("short")..R.."> ", false
    elseif style == "pure" then
        local s = ESC.."[34m"..cwd()..R
        local branch = git_branch()
        if branch then s = s.." "..ESC.."[90m"..branch..R end
        local c = ok and ESC.."[35m" or ESC.."[31m"
        return s.."\n"..c.."❯"..R.." ", false
    elseif style == "minimal" then
        local c = ok and ESC.."[32m" or ESC.."[31m"
        return ESC.."[1;36m"..cwd("leaf")..R.." "..c.."❯"..R.." ", false
    elseif style == "macos" then
        return user.."@"..hostname.." "..cwd("leaf").." % ", false
    else
        local s = ESC.."[92m"..user.."@"..hostname..R..":"..ESC.."[94m"..cwd()..R
        local branch = git_branch()
        if branch then s = s.." "..ESC.."[95m("..branch..")"..R end
        local sym = ok and ESC.."[92m$" or ESC.."[91m$"
        return s.." "..sym..R.." ", false
    end
end
