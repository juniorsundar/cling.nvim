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
}

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
            local handler = token_handlers[line:sub(i + 1, i + 1)]
            if handler then
                local replacement = handler(ctx, cwd)
                if replacement then
                    table.insert(out, replacement)
                    i = i + 2
                else
                    table.insert(out, c)
                    i = i + 1
                end
            else
                table.insert(out, c)
                i = i + 1
            end
        end
    end
    return table.concat(out)
end

return M
