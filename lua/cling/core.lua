--- @class cling.ExecutorOpts
--- @field title? string Title for the scratch buffer window.
--- @field on_open? fun(buf: integer) Callback executed after the scratch window is opened.
--- @field on_close? fun(buf: integer) Callback executed after the terminal process closes (TermClose).
--- @field smods? table Command modifiers from nvim_create_user_command.
--- @field close_on_exit? boolean If true, wipe the buffer automatically when the terminal process exits.
--- @field no_history? boolean If true, do not update last_cmd/last_cwd/last_smods. Useful for wrapper commands that should not pollute :Cling history.
--- @field no_cwd_history? boolean If true, skip per-CWD history recording (history.add/save). Set when separate_history is disabled in config.
--- @field expand? boolean If true, expand marked tokens (@%) in cmd against the execution CWD before the shell receives it. History still records the raw line. Set only by raw-line entry points; wrapper commands stay literal.

--- @class cling.Core
--- @field last_cmd string|nil Last executed command.
--- @field last_cwd string|nil Last working directory.
--- @field last_env string|nil Last environment variables.
--- @field last_smods table|nil Last command modifiers.
--- @field cling_window integer|nil Window handle for the output buffer.
--- @field cling_buffer integer|nil Buffer handle for the output.
--- @field close_cling_window fun() Closes the compilation window.
--- @field executor fun(cmd: string, cwd: string, opts?: cling.ExecutorOpts) Executes a command.

-- Module-level state for column capture/restore
--- @type table<string,string>|nil
local _captured_columns = nil
--- @type integer|nil
local _winnew_autocmd_id = nil
--- @type table<integer,boolean>
local _cling_windows = {}

local history = require "cling.history"
local navigation = require "cling.navigation"
local expand = require "cling.expand"

local M = {} --- @class cling.Core

--- @type string|nil
M.last_cmd = nil
--- @type string|nil
M.last_cwd = nil
--- @type string|nil
M.last_env = nil
--- @type table|nil
M.last_smods = nil
--- @type integer|nil
M.cling_window = nil
--- @type integer|nil
M.cling_buffer = nil

--- Builds the vim split command string based on smods.
--- @param smods table|nil Command modifiers from nvim_create_user_command.
--- @param escaped_cmd string The fnameescape'd terminal command.
--- @return string
local function build_split_cmd(smods, escaped_cmd)
    if not smods then
        return "bot split term://" .. escaped_cmd
    end

    if smods.tab and smods.tab >= 0 then
        return "tabnew term://" .. escaped_cmd
    end

    local prefix = ""
    if smods.split == "topleft" then
        prefix = "topleft "
    elseif smods.split == "botright" then
        prefix = "botright "
    else
        prefix = "botright " -- default position
    end

    if smods.vertical then
        return prefix .. "vsplit term://" .. escaped_cmd
    else
        return prefix .. "split term://" .. escaped_cmd
    end
end

--- Clears inherited editor columns from the terminal output window.
--- Captures the user's effective column settings once on the first cling window open.
--- @param winid integer Window handle for the Cling output window.
--- @param original_win integer Window handle for the user's original window (before terminal split).
local function configure_cling_window(winid, original_win)
    -- Capture user's column settings once from the original window (before the terminal split)
    if not _captured_columns and original_win and vim.api.nvim_win_is_valid(original_win) then
        _captured_columns = {
            signcolumn = vim.wo[original_win].signcolumn,
            foldcolumn = vim.wo[original_win].foldcolumn,
            statuscolumn = vim.wo[original_win].statuscolumn,
        }
    end

    vim.wo[winid].signcolumn = "no"
    vim.wo[winid].foldcolumn = "0"
    vim.wo[winid].statuscolumn = ""

    -- Create WinNew autocommand once to restore columns on non-cling windows
    if not _winnew_autocmd_id then
        _winnew_autocmd_id = vim.api.nvim_create_autocmd("WinNew", {
            group = vim.api.nvim_create_augroup("cling_column_restore", { clear = true }),
            callback = function()
                if _captured_columns then
                    local new_win = vim.api.nvim_get_current_win()
                    if not _cling_windows[new_win] then
                        vim.wo[new_win].signcolumn = _captured_columns.signcolumn
                        vim.wo[new_win].foldcolumn = _captured_columns.foldcolumn
                        vim.wo[new_win].statuscolumn = _captured_columns.statuscolumn
                    end
                end
            end,
        })
    end

    -- Track this cling window so the WinNew callback skips it
    _cling_windows[winid] = true
end

--- Removes a window from cling tracking. When no cling windows remain,
--- deletes the WinNew autocommand and clears captured columns.
--- @param winid integer
local function _untrack_window(winid)
    _cling_windows[winid] = nil
    if vim.tbl_isempty(_cling_windows) then
        _captured_columns = nil
        if _winnew_autocmd_id then
            pcall(vim.api.nvim_del_autocmd, _winnew_autocmd_id)
            _winnew_autocmd_id = nil
        end
    end
end

--- Closes the active cling output window and resets its handle.
--- Checks if the buffer and window are valid before attempting to close/delete them.
function M.close_cling_window()
    local win = M.cling_window
    local buf = M.cling_buffer
    local buf_is_valid = buf and vim.api.nvim_buf_is_valid(buf)

    if buf_is_valid then
        -- BufWipeout autocmd handles _untrack_window synchronously
        vim.api.nvim_buf_delete(buf, { force = true })
    end
    M.cling_buffer = nil

    if win and vim.api.nvim_win_is_valid(win) then
        if not buf_is_valid then
            _untrack_window(win)
        end
        vim.api.nvim_win_close(win, true)
    end
    M.cling_window = nil
end

--- Executes a shell command in a given working directory and streams output
--- to a dedicated scratch window.
---
--- @param cmd string Shell command to execute.
--- @param cwd string Working directory for the command.
--- @param opts? cling.ExecutorOpts Optional configuration for the execution.
function M.executor(cmd, cwd, opts)
    opts = opts or {}
    if M.cling_window ~= nil then
        M.close_cling_window()
    end

    if not cmd then
        vim.notify("No command to execute", vim.log.levels.ERROR)
        return
    end
    if not opts.no_history then
        M.last_cmd = cmd
        M.last_cwd = cwd
        M.last_smods = opts.smods
        if not opts.no_cwd_history then
            history.add(cwd, cmd)
            history.save(cwd)
        end
    end

    local original_window = vim.api.nvim_get_current_win()
    local actual_cwd = cwd or vim.fn.getcwd()

    if opts.expand then
        cmd = expand.expand(cmd, actual_cwd, {
            context = {
                context_provider = {
                    current_file = function()
                        return vim.fn.expand "%:p"
                    end,
                    alternate_file = function()
                        return vim.fn.expand "#"
                    end,
                    buffer_file = function(n)
                        return vim.fn.expand("#" .. n)
                    end,
                    cursor_word = function()
                        return vim.fn.expand "<cword>"
                    end,
                    cursor_WORD = function()
                        return vim.fn.expand "<cWORD>"
                    end,
                    cursor_file = function()
                        return vim.fn.expand "<cfile>"
                    end,
                },
            },
        })
    end

    if M.last_env then
        cmd = ". " .. M.last_env .. " && " .. cmd
        M.last_env = nil
    end

    local full_command_string = "cd " .. vim.fn.shellescape(actual_cwd, true) .. " && "
    full_command_string = full_command_string .. cmd
    local term_command = "sh -c " .. vim.fn.shellescape(full_command_string, true)
    local escaped_cmd = vim.fn.fnameescape(term_command)

    if not cmd or cmd == "" then
        vim.notify("Error: 'cmd' is required.", vim.log.levels.ERROR)
        return
    end

    vim.cmd(build_split_cmd(opts.smods, escaped_cmd))

    M.cling_buffer = vim.api.nvim_get_current_buf()
    M.cling_window = vim.api.nvim_get_current_win()
    configure_cling_window(M.cling_window, original_window)
    vim.api.nvim_buf_set_name(M.cling_buffer, opts.title or "[Cling]")

    vim.api.nvim_buf_set_keymap(M.cling_buffer, "n", "q", "", {
        callback = function()
            M.close_cling_window()
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(M.cling_buffer, "n", "<CR>", "", {
        callback = function()
            local line = vim.api.nvim_get_current_line()
            local cfile = vim.fn.expand "<cfile>"
            navigation.jump_to(line, cfile, actual_cwd, original_window)
        end,
        noremap = true,
        silent = true,
    })

    vim.api.nvim_buf_set_keymap(M.cling_buffer, "n", "ge", "", {
        callback = function()
            local ok, filepath = pcall(vim.fn.input, "Export to: ", vim.fn.getcwd() .. "/cling-output.log", "file")
            if not ok or not filepath or filepath == "" then
                return
            end
            navigation.export(M.cling_buffer, M.last_cmd, actual_cwd, filepath)
        end,
        noremap = true,
        silent = true,
        desc = "Export Cling output to file",
    })

    if opts.on_open then
        opts.on_open(M.cling_buffer)
    end

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = M.cling_buffer,
        once = true,
        callback = function()
            local win = M.cling_window
            if win then
                _untrack_window(win)
            end
            M.cling_window = nil
        end,
    })

    if opts.close_on_exit or opts.on_close then
        local close_buf = M.cling_buffer
        vim.api.nvim_create_autocmd("TermClose", {
            buffer = close_buf,
            once = true,
            callback = function()
                vim.schedule(function()
                    if opts.on_close then
                        opts.on_close(close_buf)
                    end
                    if opts.close_on_exit and vim.api.nvim_buf_is_valid(close_buf) then
                        vim.api.nvim_buf_delete(close_buf, { force = true })
                    end
                end)
            end,
        })
    end
end

--- Resets column capture and WinNew autocommand state (for test cleanup).
function M._reset_column_capture()
    _captured_columns = nil
    _cling_windows = {}
    if _winnew_autocmd_id then
        pcall(vim.api.nvim_del_autocmd, _winnew_autocmd_id)
        _winnew_autocmd_id = nil
    end
end

--- Adds a window to the cling tracking set (for test use only).
--- Needed to test multi-window teardown behavior without changing the public executor() API.
--- @param winid integer Window handle to track as a cling window.
function M._track_window(winid)
    _cling_windows[winid] = true
end

return M
