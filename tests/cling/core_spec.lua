local core = require "cling.core"
local history = require "cling.history"

describe("core", function()
    before_each(function()
        if core.cling_window and vim.api.nvim_win_is_valid(core.cling_window) then
            vim.api.nvim_win_close(core.cling_window, true)
        end

        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local name = vim.api.nvim_buf_get_name(buf)
            if name:match "%[Cling%]" then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end

        core.cling_window = nil
        core.cling_buffer = nil
        core.last_cmd = nil
        core.last_cwd = nil
        core.last_smods = nil

        history.clear "/tmp"
        history.clear "/var"
        history.clear "/previous"

        while vim.fn.tabpagenr "$" > 1 do
            vim.cmd "tabclose $"
        end
    end)

    describe("executor", function()
        it("opens a split window with terminal", function()
            local original_getcwd = vim.fn.getcwd
            vim.fn.getcwd = function()
                return "/tmp"
            end

            local initial_wins = #vim.api.nvim_list_wins()

            core.executor("echo hello", "/tmp")

            local final_wins = #vim.api.nvim_list_wins()
            assert.is_true(final_wins > initial_wins, "A new window should have been opened")
            assert.is_not_nil(core.cling_window)
            assert.is_not_nil(core.cling_buffer)

            vim.fn.getcwd = original_getcwd
        end)

        it("closes existing window before opening new one", function()
            core.executor("echo 1", "/tmp")
            local win1 = core.cling_window
            assert.is_not_nil(win1)

            core.executor("echo 2", "/tmp")
            local win2 = core.cling_window
            assert.is_not_nil(win2)

            assert.are_not_equal(win1, win2, "Should have created a new window handle (or reused/reset)")
            if vim.api.nvim_win_is_valid(win1) then
                -- Ideally win1 should be closed or invalid if it was a different window ID,
                -- but if splits are managed differently it might be tricky.
                -- In core.lua:
                -- if M.cling_window ~= nil then M.close_cling_window() end
                -- So win1 should definitely be invalid if it was closed.
                assert.is_false(vim.api.nvim_win_is_valid(win1), "Old window should be closed")
            end
        end)

        it("sets last_cmd and last_cwd", function()
            core.executor("ls", "/var")
            assert.are.same("ls", core.last_cmd)
            assert.are.same("/var", core.last_cwd)
        end)

        it("does not update last_cmd/last_cwd when no_history is true", function()
            core.last_cmd = "previous"
            core.last_cwd = "/previous"
            core.executor("ls", "/var", { no_history = true })
            assert.are.same("previous", core.last_cmd)
            assert.are.same("/previous", core.last_cwd)
        end)

        it("updates last_cmd/last_cwd when no_history is false", function()
            core.last_cmd = "previous"
            core.last_cwd = "/previous"
            core.executor("ls", "/var", { no_history = false })
            assert.are.same("ls", core.last_cmd)
            assert.are.same("/var", core.last_cwd)
        end)
    end)

    describe("close_cling_window", function()
        it("closes the window and buffer", function()
            core.executor("echo test", "/tmp")
            local buf = core.cling_buffer

            core.close_cling_window()

            assert.is_nil(core.cling_window)
            assert.is_nil(core.cling_buffer)
            assert.is_false(vim.api.nvim_buf_is_valid(buf), "Buffer should be deleted")
        end)
    end)

    describe("split modes", function()
        it("defaults to bottom horizontal split when no smods", function()
            local initial_wins = #vim.api.nvim_list_wins()
            core.executor("echo hello", "/tmp")
            local final_wins = #vim.api.nvim_list_wins()
            assert.is_true(final_wins > initial_wins, "A new window should have been opened")
            assert.is_not_nil(core.cling_window)
        end)

        it("opens a vertical split with smods.vertical", function()
            local initial_wins = #vim.api.nvim_list_wins()
            core.executor("echo hello", "/tmp", { smods = { vertical = true, tab = -1, split = "" } })
            local final_wins = #vim.api.nvim_list_wins()
            assert.is_true(final_wins > initial_wins, "A new window should have been opened")
            assert.is_not_nil(core.cling_window)
            assert.is_not_nil(core.cling_buffer)
        end)

        it("opens a new tab with smods.tab >= 0", function()
            local initial_tabs = vim.fn.tabpagenr "$"
            core.executor("echo hello", "/tmp", { smods = { vertical = false, tab = 0, split = "" } })
            local final_tabs = vim.fn.tabpagenr "$"
            assert.is_true(final_tabs > initial_tabs, "A new tab should have been opened")
            assert.is_not_nil(core.cling_window)
            assert.is_not_nil(core.cling_buffer)
        end)

        it("opens a topleft split with smods.split topleft", function()
            local initial_wins = #vim.api.nvim_list_wins()
            core.executor("echo hello", "/tmp", { smods = { vertical = false, tab = -1, split = "topleft" } })
            local final_wins = #vim.api.nvim_list_wins()
            assert.is_true(final_wins > initial_wins, "A new window should have been opened")
        end)

        it("saves last_smods from opts", function()
            core.executor("echo hello", "/tmp", { smods = { vertical = true, tab = -1, split = "" } })
            assert.are.same(true, core.last_smods.vertical)
            assert.are.same(-1, core.last_smods.tab)
        end)

        it("saves nil last_smods when no smods provided", function()
            core.executor("echo hello", "/tmp")
            assert.is_nil(core.last_smods)
        end)
    end)

    describe("close_on_exit", function()
        it("does NOT register a TermClose autocmd when close_on_exit is false", function()
            core.executor("echo hello", "/tmp", { close_on_exit = false })
            local buf = core.cling_buffer
            assert.is_not_nil(buf)

            local autocmds = vim.api.nvim_get_autocmds { event = "TermClose", buffer = buf }
            assert.are.same(0, #autocmds, "No TermClose autocmd should be registered when close_on_exit is false")
        end)

        it("does NOT register a TermClose autocmd when close_on_exit is omitted", function()
            core.executor("echo hello", "/tmp")
            local buf = core.cling_buffer
            assert.is_not_nil(buf)

            local autocmds = vim.api.nvim_get_autocmds { event = "TermClose", buffer = buf }
            assert.are.same(0, #autocmds, "No TermClose autocmd should be registered by default")
        end)

        it("registers a TermClose autocmd when close_on_exit is true", function()
            core.executor("echo hello", "/tmp", { close_on_exit = true })
            local buf = core.cling_buffer
            assert.is_not_nil(buf)

            local autocmds = vim.api.nvim_get_autocmds { event = "TermClose", buffer = buf }
            assert.are.same(
                1,
                #autocmds,
                "Exactly one TermClose autocmd should be registered when close_on_exit is true"
            )
        end)

        it("registers a TermClose autocmd when on_close is provided (close_on_exit omitted)", function()
            core.executor("echo hello", "/tmp", { on_close = function(_buf) end })
            local buf = core.cling_buffer
            assert.is_not_nil(buf)

            local autocmds = vim.api.nvim_get_autocmds { event = "TermClose", buffer = buf }
            assert.are.same(
                1,
                #autocmds,
                "Exactly one TermClose autocmd should be registered when on_close is provided"
            )
        end)

        it("wipes the buffer after the process exits when close_on_exit is true", function()
            core.executor("true", "/tmp", { close_on_exit = true })
            local buf = core.cling_buffer
            assert.is_not_nil(buf)

            vim.wait(3000, function()
                return not vim.api.nvim_buf_is_valid(buf)
            end, 50)

            assert.is_false(
                vim.api.nvim_buf_is_valid(buf),
                "Buffer should be wiped after process exits with close_on_exit=true"
            )
        end)

        it("does NOT wipe the buffer after process exits when close_on_exit is false", function()
            core.executor("true", "/tmp", { close_on_exit = false })
            local buf = core.cling_buffer
            assert.is_not_nil(buf)

            vim.wait(3000, function()
                return not vim.api.nvim_buf_is_valid(buf)
            end, 50)

            assert.is_true(
                vim.api.nvim_buf_is_valid(buf),
                "Buffer should persist after process exits when close_on_exit=false"
            )
        end)

        it("calls on_close with the buffer handle after the process exits", function()
            local called_with = nil
            core.executor("true", "/tmp", {
                close_on_exit = false,
                on_close = function(buf)
                    called_with = buf
                end,
            })
            local buf = core.cling_buffer
            assert.is_not_nil(buf)

            vim.wait(3000, function()
                return called_with ~= nil
            end, 50)

            assert.are.same(buf, called_with, "on_close should be called with the terminal buffer handle")
        end)

        it("calls on_close AND wipes buffer when both on_close and close_on_exit are set", function()
            local called_with = nil
            core.executor("true", "/tmp", {
                close_on_exit = true,
                on_close = function(buf)
                    called_with = buf
                end,
            })
            local buf = core.cling_buffer
            assert.is_not_nil(buf)

            vim.wait(3000, function()
                return called_with ~= nil and not vim.api.nvim_buf_is_valid(buf)
            end, 50)

            assert.are.same(buf, called_with, "on_close should be called with the terminal buffer handle")
            assert.is_false(vim.api.nvim_buf_is_valid(buf), "Buffer should be wiped when close_on_exit is true")
        end)
    end)

    describe("export", function()
        it("registers ge keymap on the output buffer", function()
            core.executor("echo hello", "/tmp")
            local keymaps = vim.api.nvim_buf_get_keymap(core.cling_buffer, "n")
            local found_ge = false
            for _, km in ipairs(keymaps) do
                if km.lhs == "ge" then
                    found_ge = true
                    break
                end
            end
            assert.is_true(found_ge, "ge keymap should be registered on the buffer")
        end)

        it("exports buffer content to file with metadata", function()
            core.executor("echo test_export", "/tmp")

            local original_input = vim.fn.input
            vim.fn.input = function(...)
                return "/tmp/cling_test_export.log"
            end

            local keymaps = vim.api.nvim_buf_get_keymap(core.cling_buffer, "n")
            local ge_callback = nil
            for _, km in ipairs(keymaps) do
                if km.lhs == "ge" then
                    ge_callback = km.callback
                    break
                end
            end

            assert.is_not_nil(ge_callback, "ge callback should exist")
            ge_callback()

            vim.fn.input = original_input

            local lines = vim.fn.readfile "/tmp/cling_test_export.log"
            assert.is_not_nil(lines, "exported file should exist")

            local found_cmd = false
            local found_cwd = false
            local found_ts = false
            local found_vim = false

            for _, line in ipairs(lines) do
                if line:match "^-- Command: echo test_export" then
                    found_cmd = true
                end
                if line:match "^-- CWD: /tmp" then
                    found_cwd = true
                end
                if line:match "^-- Timestamp: " then
                    found_ts = true
                end
                if line:match "^-- vim: ft=log$" then
                    found_vim = true
                end
            end

            assert.is_true(found_cmd, "metadata should contain Command line")
            assert.is_true(found_cwd, "metadata should contain CWD line")
            assert.is_true(found_ts, "metadata should contain Timestamp line")
            assert.is_true(found_vim, "metadata should contain vim modeline")

            os.remove "/tmp/cling_test_export.log"
        end)

        it("export preserves ANSI escape codes", function()
            core.executor("echo hello", "/tmp")

            vim.bo[core.cling_buffer].modifiable = true
            vim.api.nvim_buf_set_lines(core.cling_buffer, 0, -1, false, {
                "\27[31mred text\27[0m",
                "\27[1;32mbold green\27[0m",
                "plain line",
            })

            local original_input = vim.fn.input
            vim.fn.input = function(...)
                return "/tmp/cling_test_ansi.log"
            end

            local keymaps = vim.api.nvim_buf_get_keymap(core.cling_buffer, "n")
            local ge_callback = nil
            for _, km in ipairs(keymaps) do
                if km.lhs == "ge" then
                    ge_callback = km.callback
                    break
                end
            end

            assert.is_not_nil(ge_callback, "ge callback should exist")
            ge_callback()

            vim.fn.input = original_input

            local lines = vim.fn.readfile "/tmp/cling_test_ansi.log"
            assert.is_not_nil(lines, "exported file should exist")

            local found_red = false
            local found_green = false
            local found_plain = false
            local found_ansi = false

            for _, line in ipairs(lines) do
                if line:match "red text" then
                    found_red = true
                end
                if line:match "bold green" then
                    found_green = true
                end
                if line:match "^plain line$" then
                    found_plain = true
                end
                if line:match "\27%[" then
                    found_ansi = true
                end
            end

            assert.is_true(found_red, "output should contain 'red text'")
            assert.is_true(found_green, "output should contain 'bold green'")
            assert.is_true(found_plain, "output should contain 'plain line'")
            assert.is_true(found_ansi, "output should contain raw ANSI escape sequences")

            os.remove "/tmp/cling_test_ansi.log"
        end)

        it("export cancels when input is empty", function()
            core.executor("echo hello", "/tmp")

            local original_input = vim.fn.input
            vim.fn.input = function(...)
                return ""
            end

            local keymaps = vim.api.nvim_buf_get_keymap(core.cling_buffer, "n")
            local ge_callback = nil
            for _, km in ipairs(keymaps) do
                if km.lhs == "ge" then
                    ge_callback = km.callback
                    break
                end
            end

            assert.is_not_nil(ge_callback, "ge callback should exist")
            ge_callback()

            vim.fn.input = original_input

            local stat = vim.uv.fs_stat "/tmp/cling_test_cancel.log"
            assert.is_nil(stat, "no file should have been created when input is empty")
        end)
    end)
end)
