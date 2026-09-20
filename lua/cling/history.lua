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
--- Caps at 100 entries, evicting oldest first.
--- @param cwd string
--- @param cmd string
function M.add(cwd, cmd)
    _cache[cwd] = _cache[cwd] or {}
    local list = _cache[cwd]

    for i = #list, 1, -1 do
        if list[i] == cmd then
            table.remove(list, i)
            break
        end
    end

    table.insert(list, cmd)

    while #list > DEFAULT_MAX do
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
        local ok = pcall(vim.fn.mkdir, dir, "p")
        if not ok and vim.fn.isdirectory(dir) == 0 then
            vim.notify("Error: cannot create directory " .. dir, vim.log.levels.ERROR)
            return
        end
    end
    local list = _cache[cwd] or {}
    local lines = { "return {" }
    for _, cmd in ipairs(list) do
        table.insert(lines, string.format("  %q,", cmd))
    end
    table.insert(lines, "}")
    vim.fn.writefile(lines, history_path(cwd))
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
