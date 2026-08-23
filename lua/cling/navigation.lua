--- Terminal-output operations: exporting buffer content with a metadata footer.

local fs = require "cling.fs"

--- Errorformat used to parse locations out of terminal output lines.
local DEFAULT_EFM = table.concat({
    "%f:%l:%c:%m",
    "%f:%l:%c",
    "%f:%l",
}, ",")

local M = {} --- @class cling.Navigation

--- Jumps to the file location described by a line of terminal output.
--- Known limitations (preserved from the original executor callback):
--- - `cfile` is used for path resolution, not the efm-parsed filename.
--- - Silently returns when the file doesn't exist at either path.
--- - No guard on empty parse results; a non-matching line errors on items[1].
--- @param line string The terminal output line containing the location.
--- @param cfile string The file path under the cursor (`<cfile>`).
--- @param cwd string Working directory used to resolve relative paths.
--- @param target_win integer Window in which to open the file.
function M.jump_to(line, cfile, cwd, target_win)
    local start_idx = line:find(cfile, 1, true)
    if not start_idx then
        print "Path not found on current line"
        return
    end
    local trimmed_line = line:sub(start_idx)

    local qf = vim.fn.getqflist { lines = { trimmed_line }, efm = DEFAULT_EFM }
    local lnum = qf.items[1].lnum
    local col = qf.items[1].col

    local full_path = vim.fs.normalize(vim.fs.joinpath(cwd, cfile))
    if not vim.uv.fs_stat(full_path) and vim.uv.fs_stat(cfile) then
        full_path = vim.fs.normalize(cfile)
    end
    if not vim.uv.fs_stat(full_path) then
        return nil
    end

    if not vim.api.nvim_win_is_valid(target_win) then
        vim.notify("Original window is no longer valid", vim.log.levels.ERROR)
        return
    end

    local open_to_cmd = "edit +" .. lnum .. " " .. vim.fn.fnameescape(full_path)
    if type(col) == "number" and col > 0 then
        open_to_cmd = open_to_cmd .. " | normal! " .. col .. "|"
    end

    vim.fn.win_execute(target_win, open_to_cmd)
    vim.api.nvim_set_current_win(target_win)
end

--- Exports the terminal buffer output to a file, appending a metadata footer.
--- @param buf integer Buffer handle for the output.
--- @param cmd string|nil The command that produced the output.
--- @param cwd string|nil The working directory of the command.
--- @param filepath string Destination file path.
function M.export(buf, cmd, cwd, filepath)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    -- Remove trailing empty lines
    while #lines > 0 and lines[#lines] == "" do
        table.remove(lines)
    end

    -- Append metadata footer
    table.insert(lines, "")
    table.insert(lines, "-- Command: " .. (cmd or "unknown"))
    table.insert(lines, "-- CWD: " .. (cwd or "unknown"))
    table.insert(lines, "-- Timestamp: " .. os.date "!%Y-%m-%dT%H:%M:%SZ")
    table.insert(lines, "-- vim: ft=log")

    local content = table.concat(lines, "\n") .. "\n"
    if fs.write_file(filepath, content) then
        vim.notify("Output exported to " .. filepath, vim.log.levels.INFO)
    else
        vim.notify("Failed to export to " .. filepath, vim.log.levels.ERROR)
    end
end

return M
