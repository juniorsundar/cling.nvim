--- @class cling.ExecutorOpts
--- @field title? string Title for the scratch buffer window.
--- @field on_open? fun(buf: integer) Callback executed after the scratch window is opened.

--- @class cling.Core
--- @field last_cmd string|nil Last executed command.
--- @field last_cwd string|nil Last working directory.
--- @field last_env string|nil Last environment variables.
--- @field cling_window integer|nil Window handle for the output buffer.
--- @field cling_buffer integer|nil Buffer handle for the output.
--- @field close_cling_window fun() Closes the compilation window.
--- @field executor fun(cmd: string, cwd: string, opts?: cling.ExecutorOpts) Executes a command.

local M = {} --- @class cling.Core

--- @type string|nil
M.last_cmd = nil
--- @type string|nil
M.last_cwd = nil
--- @type string|nil
M.last_env = nil
--- @type integer|nil
M.cling_window = niljuniorsundar / cling.nvim
--- @type integer|nil
M.cling_buffer = nil

--- Closes the active cling output window and resets its handle.
--- Checks if the buffer and window are valid before attempting to close/delete them.
function M.close_cling_window()
    if M.cling_buffer and vim.api.nvim_buf_is_valid(M.cling_buffer) then
        vim.api.nvim_buf_delete(M.cling_buffer, { force = true })
    end
    M.cling_buffer = nil

    if M.cling_window and vim.api.nvim_win_is_valid(M.cling_window) then
        vim.api.nvim_win_close(M.cling_window, true)
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
    M.last_cmd = cmd
    M.last_cwd = cwd

    -- Handle environment variables from .env
    if M.last_env then
        cmd = ". " .. M.last_env .. " && " .. cmd
        M.last_env = nil
    end

    local original_window = vim.api.nvim_get_current_win()
    local actual_cwd = cwd or vim.fn.getcwd()
    local full_command_string = "cd " .. vim.fn.shellescape(actual_cwd, true) .. " && "

    full_command_string = full_command_string .. cmd
    local term_command = "sh -c " .. vim.fn.shellescape(full_command_string, true)
    local escaped_cmd = vim.fn.fnameescape(term_command)

    if not cmd or cmd == "" then
        vim.notify("Error: 'cmd' is required.", vim.log.levels.ERROR)
        return
    end

    vim.cmd("bot split term://" .. escaped_cmd)

    M.cling_buffer = vim.api.nvim_get_current_buf()
    M.cling_window = vim.api.nvim_get_current_win()
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
            local start_idx = line:find(cfile, 1, true)
            if not start_idx then
                print "Path not found on current line"
                return
            end
            local trimmed_line = line:sub(start_idx)

            local original_qf_state = vim.fn.getqflist { all = 0 }
            local original_efm = vim.go.errorformat

            local temp_efm = table.concat({
                "%f:%l:%c:%m",
                "%f:%l:%c",
                "%f:%l",
            }, ",")
            vim.go.errorformat = temp_efm .. "," .. original_efm
            vim.fn.setqflist({}, "r", { lines = { trimmed_line } })
            local qf_items = vim.fn.getqflist()

            vim.go.errorformat = original_efm
            vim.fn.setqflist({}, "r", {
                items = original_qf_state.items,
                title = original_qf_state.title,
            })

            local lnum = qf_items[1].lnum
            local col = qf_items[1].col

            local full_path = vim.fs.normalize(vim.fs.joinpath(actual_cwd, cfile))
            if not vim.uv.fs_stat(full_path) and vim.uv.fs_stat(cfile) then
                full_path = vim.fs.normalize(cfile)
            end
            if not vim.uv.fs_stat(full_path) then
                return nil
            end

            if not vim.api.nvim_win_is_valid(original_window) then
                vim.notify("Original window is no longer valid", vim.log.levels.ERROR)
                return
            end

            local open_to_cmd = "edit +" .. lnum .. " " .. vim.fn.fnameescape(full_path)
            if type(col) == "number" and col > 0 then
                open_to_cmd = open_to_cmd .. " | normal! " .. col .. "|"
            end

            vim.fn.win_execute(original_window, open_to_cmd)
            vim.api.nvim_set_current_win(original_window)
        end,
        noremap = true,
        silent = true,
    })

    if opts.on_open then
        opts.on_open(M.cling_buffer)
    end

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = M.cling_buffer,
        once = true,
        callback = function()
            M.cling_window = nil
        end,
    })
end

return M
