--- @class cling.ExecutorOpts
--- @field title? string Title for the scratch buffer window.
--- @field keymaps? fun(buf: integer) Applies custom keymaps to the output buffer after it is opened.
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
--- @return string
local function build_split_cmd(smods)
    if not smods then
        return "botright new"
    end

    if smods.tab and smods.tab >= 0 then
        return "tabnew"
    end

    local prefix = ""
    if smods.split == "topleft" then
        prefix = "topleft "
    else
        prefix = "botright " -- default position
    end

    if smods.vertical then
        return prefix .. "vnew"
    else
        return prefix .. "new"
    end
end

--- Closes the active cling output window and resets its handle.
--- Checks if the buffer and window are valid before attempting to close/delete them.
function M.close_cling_window()
    local win = M.cling_window
    local buf = M.cling_buffer
    local buf_is_valid = buf and vim.api.nvim_buf_is_valid(buf)

    if buf_is_valid then
        vim.api.nvim_buf_delete(buf, { force = true })
    end
    M.cling_buffer = nil

    if win and vim.api.nvim_win_is_valid(win) then
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

    local actual_cwd = cwd or vim.fn.getcwd()
    actual_cwd = vim.fn.expand(actual_cwd)
    if vim.fn.isdirectory(actual_cwd) ~= 1 then
        vim.notify("Error: not a valid directory: " .. actual_cwd, vim.log.levels.ERROR)
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

    if opts.expand then
        cmd = expand.expand(cmd, actual_cwd)
    end

    if M.last_env then
        cmd = ". " .. M.last_env .. " && " .. cmd
        M.last_env = nil
    end

    if not cmd or cmd == "" then
        vim.notify("Error: 'cmd' is required.", vim.log.levels.ERROR)
        return
    end

    -- Run in the job's own working directory via termopen's cwd option:
    -- no `cd <dir> &&` shell prefix, no command in the buffer name.
    local term_command = "sh -c " .. vim.fn.shellescape(cmd, true)

    vim.cmd(build_split_cmd(opts.smods))
    vim.fn.termopen(term_command, { cwd = actual_cwd })

    M.cling_buffer = vim.api.nvim_get_current_buf()
    M.cling_window = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_name(M.cling_buffer, opts.title or "[Cling]")

    vim.keymap.set("n", "q", M.close_cling_window, { buffer = M.cling_buffer, silent = true })

    vim.keymap.set("n", "<CR>", function()
        navigation.jump_to(vim.api.nvim_get_current_line(), vim.fn.expand "<cfile>", actual_cwd, original_window)
    end, { buffer = M.cling_buffer, silent = true })

    vim.keymap.set("n", "ge", function()
        local ok, filepath = pcall(vim.fn.input, "Export to: ", vim.fn.getcwd() .. "/cling-output.log", "file")
        if ok and filepath and filepath ~= "" then
            navigation.export(M.cling_buffer, M.last_cmd, actual_cwd, filepath)
        end
    end, { buffer = M.cling_buffer, silent = true, desc = "Export Cling output to file" })

    if opts.keymaps then
        opts.keymaps(M.cling_buffer)
    end

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = M.cling_buffer,
        once = true,
        callback = function()
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

return M
