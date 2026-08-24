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

--- Expands marked tokens in a raw Cling command line against the execution CWD.
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
                    table.insert(out, replacement)
                    i = i + 1 + consumed + 1
                else
                    -- No usable @#N form; fall back to the bare-@# handler.
                    local fallback = token_handlers["#"](ctx, cwd)
                    if fallback then
                        table.insert(out, fallback)
                        i = i + 2
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
                if replacement then
                    table.insert(out, replacement)
                    i = i + consumed_len
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
