--- Marker-based (`@`) filename expansion for Cling command lines.
---
--- Pure transformation: `(raw command line, execution CWD) → expanded command
--- line`. A marker `@` immediately followed by a recognized token is consumed
--- and the token resolves via native `expand()`; every other character —
--- including any other `@` — passes through verbatim. `@@` yields a single
--- literal `@`. Relative paths absolutize against the execution CWD, not the
--- editor's current working directory.

local M = {}

--- Absolutizes a path against the execution CWD.
local function absolutize(path, cwd)
    if not vim.startswith(path, "/") then
        path = vim.fs.joinpath(cwd, path)
    end
    return vim.fn.fnamemodify(path, ":p")
end

--- Multi-character tokens, tried longest-first after the marker.
local MULTICHAR_TOKENS = { "<cWORD>", "<cword>", "<cfile>" }

--- Resolves the token following the marker at `i` through native expand().
--- Returns the replacement and the number of characters consumed (including
--- the marker), or nil when the token resolves to nothing.
local function resolve_token(line, i, cwd)
    local rest = line:sub(i + 1)
    if rest:sub(1, 1) == "%" then
        local file = vim.fn.expand "%"
        if file == "" then
            return nil
        end
        return absolutize(file, cwd), 2
    end
    if rest:sub(1, 1) == "#" then
        local digits = rest:match "^#(%d+)"
        local file = vim.fn.expand(digits and "#" .. digits or "#")
        if file == "" then
            return nil
        end
        return absolutize(file, cwd), digits and #digits + 2 or 2
    end
    for _, token in ipairs(MULTICHAR_TOKENS) do
        if rest:sub(1, #token) == token then
            local value = vim.fn.expand(token)
            if value == "" then
                return nil
            end
            if token == "<cfile>" then
                value = absolutize(value, cwd)
            end
            return value, #token + 1
        end
    end
    return nil
end

--- Parses a chain of filename modifiers following a token site.
--- Returns the list of modifiers, characters consumed, and an "unsupported"
--- flag when a substitution modifier (`:s///`, `:gs///`) is encountered — in
--- that case the whole marked site falls back to passthrough rather than
--- being partially parsed.
local function parse_modifiers(line, start)
    local mods = {}
    local j = start
    local at_start = true
    while true do
        -- `.` and `~` are valid modifiers without a leading colon, but only as
        -- the first modifier (e.g. `@%.`); once a `:mod` is seen, continuation
        -- requires another colon (`@%:r.o` leaves `.o` literal).
        local has_colon = line:sub(j, j) == ":"
        local m = has_colon and line:sub(j + 1, j + 1) or line:sub(j, j)
        if (not has_colon and m ~= "." and m ~= "~") or (not has_colon and not at_start) then
            break
        end
        if m:match "^[p~%.htreqS]$" then
            table.insert(mods, m)
            j = j + (has_colon and 2 or 1)
            at_start = false
        elseif m == "s" or (m == "g" and line:sub(j + 2, j + 2) == "s") then
            return nil, nil, true
        else
            break
        end
    end
    return mods, j - start, false
end

--- Applies a modifier chain left-to-right. `:p` and `:.` resolve against the
--- execution CWD; `:S`/`:q` shell-quote; the rest are native fnamemodify.
local function apply_modifiers(text, mods, cwd)
    for _, m in ipairs(mods) do
        if m == "p" then
            text = absolutize(text, cwd)
        elseif m == "." then
            local norm = cwd:sub(-1) == "/" and cwd:sub(1, -2) or cwd
            if text == norm then
                text = "."
            elseif vim.startswith(text, norm .. "/") then
                text = "." .. text:sub(#norm + 1)
            end
        elseif m == "S" or m == "q" then
            text = vim.fn.shellescape(text)
        else
            text = vim.fn.fnamemodify(text, ":" .. m)
        end
    end
    return text
end

---@param line string The raw typed command line.
---@param cwd string The execution working directory.
---@return string expanded The expanded command line.
function M.expand(line, cwd)
    local out = {}
    local i = 1
    while i <= #line do
        local c = line:sub(i, i)
        if c ~= "@" then
            table.insert(out, c)
            i = i + 1
        elseif line:sub(i + 1, i + 1) == "@" then
            table.insert(out, "@")
            i = i + 2
        else
            local replacement, consumed = resolve_token(line, i, cwd)
            if not replacement then
                table.insert(out, c)
                i = i + 1
            else
                local mods, mods_consumed, unsupported = parse_modifiers(line, i + consumed)
                if not unsupported then
                    table.insert(out, apply_modifiers(replacement, mods or {}, cwd))
                    i = i + consumed + (mods_consumed or 0)
                else
                    table.insert(out, c)
                    i = i + 1
                end
            end
        end
    end
    return table.concat(out)
end

return M
