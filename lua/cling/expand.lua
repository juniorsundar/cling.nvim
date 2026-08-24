--- Marker-based (`@`) filename expansion for Cling command lines.
---
--- Pure transformation: `(raw command line, execution CWD) → expanded command
--- line`. A marker `@` immediately followed by a recognized token is consumed
--- and the token expands; every other character — including any other `@` —
--- passes through verbatim. `@@` yields a single literal `@`.
---
--- Editor-dependent inputs are supplied through an injectable context provider
--- (`opts.context_provider`) so this module has no hard dependency on
--- window/buffer state during tests.

local M = {}

---@class cling.ExpandContextProvider
---@field current_file? fun(): string Resolves the current file's path.
---@field alternate_file? fun(): string Resolves the alternate file's path.

---@class cling.ExpandContext
---@field context_provider? cling.ExpandContextProvider

---@class cling.ExpandOpts
---@field cwd string The execution CWD tokens resolve against.
---@field context? cling.ExpandContext Injected editor state.

--- Recognized token handlers. Each returns the replacement string for the text
--- following the marker, or nil if the token is not recognized.
local token_handlers = {
    ["%"] = function(ctx, cwd)
        local provider = ctx and ctx.context_provider
        local current_file = provider and provider.current_file and provider.current_file()
        if not current_file or current_file == "" then
            return nil
        end
        if not vim.startswith(current_file, "/") then
            current_file = vim.fs.joinpath(cwd, current_file)
        end
        return vim.fn.fnamemodify(current_file, ":p")
    end,
    ["#"] = function(ctx, cwd)
        local provider = ctx and ctx.context_provider
        local alternate = provider and provider.alternate_file and provider.alternate_file()
        if not alternate or alternate == "" then
            return nil
        end
        if not vim.startswith(alternate, "/") then
            alternate = vim.fs.joinpath(cwd, alternate)
        end
        return vim.fn.fnamemodify(alternate, ":p")
    end,
}

--- Absolutizes a provider-supplied path against the execution CWD.
local function absolutize(path, cwd)
    if not vim.startswith(path, "/") then
        path = vim.fs.joinpath(cwd, path)
    end
    return vim.fn.fnamemodify(path, ":p")
end

--- Recognized multi-character token handlers, tried longest-first after the
--- marker. Each returns the replacement string, or nil if unrecognized/unset.
local multichar_handlers = {
    ["<cword>"] = function(ctx)
        local provider = ctx and ctx.context_provider
        local word = provider and provider.cursor_word and provider.cursor_word()
        if not word or word == "" then
            return nil
        end
        return word
    end,
    ["<cWORD>"] = function(ctx)
        local provider = ctx and ctx.context_provider
        local word = provider and provider.cursor_WORD and provider.cursor_WORD()
        if not word or word == "" then
            return nil
        end
        return word
    end,
    ["<cfile>"] = function(ctx, cwd)
        local provider = ctx and ctx.context_provider
        local file = provider and provider.cursor_file and provider.cursor_file()
        if not file or file == "" then
            return nil
        end
        return absolutize(file, cwd)
    end,
}

--- Resolves a buffer-number token (`@#N`): consumes the digits following `#`
--- and returns buffer N's file path, absolutized against the CWD.
local function buffer_number_token(ctx, cwd, line, start)
    local provider = ctx and ctx.context_provider
    if not (provider and provider.buffer_file) then
        return nil
    end
    local digits = line:match("^%d+", start)
    if not digits then
        return nil
    end
    local path = provider.buffer_file(tonumber(digits))
    if not path or path == "" then
        return nil
    end
    if not vim.startswith(path, "/") then
        path = vim.fs.joinpath(cwd, path)
    end
    return vim.fn.fnamemodify(path, ":p"), #digits
end

--- Applies a single filename modifier to a path-like string, resolving
--- relative forms (`:.`, `:~`) against the execution CWD and $HOME.
local function apply_modifier(text, mod, cwd)
    if mod == "p" then
        if not vim.startswith(text, "/") then
            text = vim.fs.joinpath(cwd, text)
        end
        return vim.fn.fnamemodify(text, ":p")
    elseif mod == "~" then
        local home = vim.env.HOME or ""
        if home ~= "" then
            if text == home then
                return "~"
            end
            local prefix = home .. "/"
            if vim.startswith(text, prefix) then
                return "~" .. text:sub(#prefix)
            end
        end
        return text
    elseif mod == "." then
        local norm_cwd = cwd:sub(-1) == "/" and cwd:sub(1, -2) or cwd
        if text == norm_cwd then
            return "."
        end
        local prefix = norm_cwd .. "/"
        if vim.startswith(text, prefix) then
            return "." .. text:sub(#prefix)
        end
        return text
    elseif mod == "S" or mod == "q" then
        return vim.fn.shellescape(text)
    else
        return vim.fn.fnamemodify(text, ":" .. mod)
    end
end

--- Parses a chain of filename modifiers following a token site.
--- Returns the list of modifiers, characters consumed, and an
--- "unsupported" flag when a substitution modifier (`:s///`, `:gs///`)
--- is encountered — in that case the whole marked site falls back to
--- passthrough rather than being partially parsed.
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

---@param line string The raw typed command line.
---@param cwd string The execution working directory.
---@param opts? cling.ExpandOpts Options with the injected context provider.
---@return string expanded The expanded command line.
function M.expand(line, cwd, opts)
    opts = opts or {}
    local ctx = opts.context
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
            local nxt = line:sub(i + 1, i + 1)
            if nxt == "#" then
                local replacement, consumed = buffer_number_token(ctx, cwd, line, i + 2)
                if replacement then
                    local mods, mods_consumed, unsupported = parse_modifiers(line, i + 1 + consumed + 1)
                    if not unsupported then
                        for _, mod in ipairs(mods or {}) do
                            replacement = apply_modifier(replacement, mod, cwd)
                        end
                        table.insert(out, replacement)
                        i = i + 1 + consumed + 1 + mods_consumed
                    else
                        table.insert(out, c)
                        i = i + 1
                    end
                else
                    -- No usable @#N form; fall back to the bare-@# handler.
                    local fallback = token_handlers["#"](ctx, cwd)
                    if fallback then
                        local mods, mods_consumed, unsupported = parse_modifiers(line, i + 2)
                        if not unsupported then
                            for _, mod in ipairs(mods or {}) do
                                fallback = apply_modifier(fallback, mod, cwd)
                            end
                            table.insert(out, fallback)
                            i = i + 2 + mods_consumed
                        else
                            table.insert(out, c)
                            i = i + 1
                        end
                    else
                        table.insert(out, c)
                        i = i + 1
                    end
                end
            else
                local replacement = nil
                local consumed_len = nil
                for token, handler in pairs(multichar_handlers) do
                    if line:sub(i + 1, i + #token) == token then
                        replacement = handler(ctx, cwd)
                        consumed_len = #token + 1
                        break
                    end
                end
                if not replacement then
                    local handler = token_handlers[nxt]
                    if handler then
                        replacement = handler(ctx, cwd)
                        consumed_len = 2
                    end
                end
                if not replacement then
                    table.insert(out, c)
                    i = i + 1
                else
                    local mods, mods_consumed, unsupported = parse_modifiers(line, i + consumed_len)
                    if not unsupported then
                        for _, mod in ipairs(mods or {}) do
                            replacement = apply_modifier(replacement, mod, cwd)
                        end
                        table.insert(out, replacement)
                        i = i + consumed_len + mods_consumed
                    else
                        table.insert(out, c)
                        i = i + 1
                    end
                end
            end
        end
    end
    return table.concat(out)
end

return M
