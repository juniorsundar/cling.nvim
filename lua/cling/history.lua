--- @class cling.History
--- Per-CWD persistent command history for cling.nvim.
--- History files are stored at stdpath("data")/cling/history/<escaped_cwd>.lua

local M = {}

--- @type table<string, string[]>
local _cache = {}
local DEFAULT_MAX = 100

--- Escape a cwd path into a safe filename component.
--- @param cwd string
--- @return string
local function escape_cwd(cwd)
    return cwd:gsub("[/\\:%% ]", "_")
end

--- Return the disk path for a given cwd's history file.
--- @param cwd string
--- @return string
local function history_path(cwd)
    return vim.fn.stdpath "data" .. "/cling/history/" .. escape_cwd(cwd) .. ".lua"
end

--- Add a command to the in-memory history for cwd.
--- Deduplicates: if cmd already exists it is moved to the end.
--- Caps at max_size (default 100), evicting oldest first.
--- @param cwd string
--- @param cmd string
--- @param opts? {max_size?: integer}
function M.add(cwd, cmd, opts)
    opts = opts or {}
    local max = opts.max_size or DEFAULT_MAX
    _cache[cwd] = _cache[cwd] or {}
    local list = _cache[cwd]

    for i = #list, 1, -1 do
        if list[i] == cmd then
            table.remove(list, i)
            break
        end
    end

    table.insert(list, cmd)

    while #list > max do
        table.remove(list, 1)
    end
end

--- Return the history list for a cwd (most recent last). Never nil.
--- @param cwd string
--- @return string[]
function M.get(cwd)
    return _cache[cwd] or {}
end

--- Persist the in-memory history for cwd to disk.
--- @param cwd string
function M.save(cwd)
    local dir = vim.fn.stdpath "data" .. "/cling/history"
    if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
    end
    local list = _cache[cwd] or {}
    local lines = { "return {" }
    for _, cmd in ipairs(list) do
        table.insert(lines, string.format("  %q,", cmd))
    end
    table.insert(lines, "}")
    local content = table.concat(lines, "\n") .. "\n"
    local fs = require "cling.fs"
    fs.write_file(history_path(cwd), content)
end

--- Load history from disk into the in-memory cache for cwd.
--- Returns the list (or {} if no file exists).
--- @param cwd string
--- @return string[]
function M.load(cwd)
    local path = history_path(cwd)
    local chunk = loadfile(path)
    if not chunk then
        return {}
    end
    local ok, result = pcall(chunk)
    if not ok or type(result) ~= "table" then
        return {}
    end
    _cache[cwd] = result
    return result
end

--- Clear the in-memory cache for cwd (does not touch disk).
--- @param cwd string
function M.clear(cwd)
    _cache[cwd] = nil
end

return M
