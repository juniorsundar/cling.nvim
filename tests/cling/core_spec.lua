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

        core._reset_column_capture()
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

        it("clears inherited statuscolumn padding in the terminal window", function()
            local saved_sc = vim.wo.signcolumn
            local saved_fc = vim.wo.foldcolumn
            local saved_scol = vim.wo.statuscolumn

            vim.wo.signcolumn = "yes"
            vim.wo.foldcolumn = "1"
            vim.wo.statuscolumn = "%l  "

            core.executor("echo hello", "/tmp")

            assert.are.same("", vim.wo[core.cling_window].statuscolumn)
            assert.are.same("no", vim.wo[core.cling_window].signcolumn)
            assert.are.same("0", vim.wo[core.cling_window].foldcolumn)

            vim.wo.signcolumn = saved_sc
            vim.wo.foldcolumn = saved_fc
            vim.wo.statuscolumn = saved_scol
        end)

        it("captures user columns before zeroing and restores them on new non-cling split", function()
            local saved_sc = vim.wo.signcolumn
            local saved_fc = vim.wo.foldcolumn
            local saved_scol = vim.wo.statuscolumn

            vim.wo.signcolumn = "yes:2"
            vim.wo.foldcolumn = "1"
            vim.wo.statuscolumn = "%l  "

            core.executor("echo hello", "/tmp")

            -- cling window is zeroed
            assert.are.same("", vim.wo[core.cling_window].statuscolumn)
            assert.are.same("no", vim.wo[core.cling_window].signcolumn)
            assert.are.same("0", vim.wo[core.cling_window].foldcolumn)

            -- create a new split window
            vim.cmd "vsplit"
            local new_win = vim.api.nvim_get_current_win()

            -- new window should have the user's original column values
            assert.are.same("yes:2", vim.wo[new_win].signcolumn, "new window should inherit captured signcolumn")
            assert.are.same("1", vim.wo[new_win].foldcolumn, "new window should inherit captured foldcolumn")
            assert.are.same("%l  ", vim.wo[new_win].statuscolumn, "new window should inherit captured statuscolumn")

            vim.wo.signcolumn = saved_sc
            vim.wo.foldcolumn = saved_fc
            vim.wo.statuscolumn = saved_scol
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

    it("cleans up WinNew autocommand and state when last cling window closes, re-captures on next open", function()
        local saved_sc = vim.wo.signcolumn
        local saved_fc = vim.wo.foldcolumn
        local saved_scol = vim.wo.statuscolumn

        -- set initial values
        vim.wo.signcolumn = "auto:3"
        vim.wo.foldcolumn = "3"
        vim.wo.statuscolumn = "%3l"

        -- first cling: capture and create autocommand
        core.executor("echo first", "/tmp")

        local autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #autocmds, "WinNew autocommand should exist after first cling open")

        -- close the cling window
        core.close_cling_window()

        -- autocommand should be deleted and state cleared
        autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(0, #autocmds, "WinNew autocommand should be deleted after last cling window closes")

        -- change column values to verify re-capture
        vim.wo.signcolumn = "yes:9"
        vim.wo.foldcolumn = "9"
        vim.wo.statuscolumn = "%9l"

        -- re-open cling: should re-capture from current window
        core.executor("echo second", "/tmp")

        -- autocommand re-created
        autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #autocmds, "WinNew autocommand should be re-created on re-open")

        -- new split should get re-captured values
        vim.cmd "vsplit"
        local new_win = vim.api.nvim_get_current_win()

        assert.are.same("yes:9", vim.wo[new_win].signcolumn, "re-captured signcolumn should be restored")
        assert.are.same("9", vim.wo[new_win].foldcolumn, "re-captured foldcolumn should be restored")
        assert.are.same("%9l", vim.wo[new_win].statuscolumn, "re-captured statuscolumn should be restored")

        vim.wo.signcolumn = saved_sc
        vim.wo.foldcolumn = saved_fc
        vim.wo.statuscolumn = saved_scol
    end)

    it("WinNew autocommand is created only once, not duplicated", function()
        -- first cling open: autocommand should be created
        core.executor("echo first", "/tmp")

        local winnew_autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #winnew_autocmds, "first cling open should create exactly one WinNew autocommand")

        -- second cling open: autocommand should NOT be duplicated
        core.executor("echo second", "/tmp")

        winnew_autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #winnew_autocmds, "second cling open should not duplicate the WinNew autocommand")

        -- third cling open: still only one
        core.executor("echo third", "/tmp")

        winnew_autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #winnew_autocmds, "third cling open should still have only one WinNew autocommand")
    end)

    it("multiple simultaneous cling windows each stay zeroed and non-cling splits get restored", function()
        local saved_sc = vim.wo.signcolumn
        local saved_fc = vim.wo.foldcolumn
        local saved_scol = vim.wo.statuscolumn

        vim.wo.signcolumn = "auto:2"
        vim.wo.foldcolumn = "2"
        vim.wo.statuscolumn = "%l/%L"

        -- first cling window
        core.executor("echo first", "/tmp")
        local win1 = core.cling_window

        -- second cling window (auto-closes first)
        core.executor("echo second", "/tmp")
        local win2 = core.cling_window

        -- first window was closed
        assert.is_false(vim.api.nvim_win_is_valid(win1), "first cling window should be closed")

        -- second cling window is zeroed
        assert.are.same("", vim.wo[win2].statuscolumn)
        assert.are.same("no", vim.wo[win2].signcolumn)
        assert.are.same("0", vim.wo[win2].foldcolumn)

        -- create a new split
        vim.cmd "vsplit"
        local new_win = vim.api.nvim_get_current_win()

        -- new non-cling window gets restored original values
        assert.are.same(
            "auto:2",
            vim.wo[new_win].signcolumn,
            "new split should get captured signcolumn after transition"
        )
        assert.are.same("2", vim.wo[new_win].foldcolumn, "new split should get captured foldcolumn after transition")
        assert.are.same(
            "%l/%L",
            vim.wo[new_win].statuscolumn,
            "new split should get captured statuscolumn after transition"
        )

        vim.wo.signcolumn = saved_sc
        vim.wo.foldcolumn = saved_fc
        vim.wo.statuscolumn = saved_scol
    end)

    -- Edge-case tests from checkpoint review

    it("BufWipeout on cling buffer triggers cleanup (no dangling autocommand)", function()
        core.executor("echo hello", "/tmp")

        -- verify WinNew autocommand exists
        local autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #autocmds, "WinNew should exist after cling open")

        -- directly delete the buffer (simulating :bd on the cling buffer)
        -- BufWipeout autocmd should fire synchronously and trigger _untrack_window
        vim.api.nvim_buf_delete(core.cling_buffer, { force = true })
        core.cling_buffer = nil
        core.cling_window = nil

        -- autocommand should be cleaned up
        autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(0, #autocmds, "WinNew should be deleted when cling buffer is wiped")
    end)

    -- Teardown-on-close tests (issue #02)

    it("q keymap triggers cleanup: tracking set emptied, WinNew autocommand deleted", function()
        core.executor("echo hello", "/tmp")

        -- verify WinNew autocommand exists
        local autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #autocmds, "WinNew should exist after cling open")

        -- simulate pressing 'q' by invoking the keymap callback directly
        local keymaps = vim.api.nvim_buf_get_keymap(core.cling_buffer, "n")
        local q_callback = nil
        for _, km in ipairs(keymaps) do
            if km.lhs == "q" then
                q_callback = km.callback
                break
            end
        end
        assert.is_not_nil(q_callback, "q keymap should be registered on the cling buffer")
        q_callback()

        -- WinNew autocommand should be deleted (last cling window closed)
        autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(0, #autocmds, "WinNew should be deleted after q closes last cling window")

        -- buffer and window handles should be cleared
        assert.is_nil(core.cling_buffer)
        assert.is_nil(core.cling_window)
    end)

    it("close_cling_window triggers cleanup: tracking set emptied, WinNew autocommand deleted", function()
        core.executor("echo hello", "/tmp")
        local buf = core.cling_buffer

        -- verify WinNew autocommand exists
        local autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #autocmds, "WinNew should exist after cling open")

        core.close_cling_window()

        -- buffer and window handles should be cleared
        assert.is_nil(core.cling_window)
        assert.is_nil(core.cling_buffer)
        assert.is_false(vim.api.nvim_buf_is_valid(buf), "Buffer should be deleted")

        -- WinNew autocommand should be deleted
        autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(0, #autocmds, "WinNew should be deleted after close_cling_window")
    end)

    it("autocommand survives when closing one cling window while another is tracked", function()
        -- capture the original (non-cling) window before executor shifts focus
        local original_win = vim.api.nvim_get_current_win()

        core.executor("echo hello", "/tmp")

        -- verify WinNew autocommand exists
        local autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #autocmds, "WinNew should exist after cling open")

        -- simulate a second cling window being tracked using the original window handle
        -- (the public executor() API auto-closes previous windows, so we use a test helper)
        core._track_window(original_win)

        -- close the actual cling window
        core.close_cling_window()

        -- autocommand should SURVIVE because original_win is still in the tracking set
        autocmds = vim.api.nvim_get_autocmds {
            event = "WinNew",
            group = "cling_column_restore",
        }
        assert.are.same(1, #autocmds, "WinNew should survive when another cling window is still tracked")
    end)

    it("restores captured columns on non-split window creation via :new", function()
        local saved_sc = vim.wo.signcolumn
        local saved_fc = vim.wo.foldcolumn
        local saved_scol = vim.wo.statuscolumn

        vim.wo.signcolumn = "auto:7"
        vim.wo.foldcolumn = "7"
        vim.wo.statuscolumn = "%7l"

        core.executor("echo hello", "/tmp")

        -- create a new empty window (not a split) — WinNew should still fire
        vim.cmd "new"
        local new_win = vim.api.nvim_get_current_win()

        assert.are.same("auto:7", vim.wo[new_win].signcolumn, ":new window should get captured signcolumn")
        assert.are.same("7", vim.wo[new_win].foldcolumn, ":new window should get captured foldcolumn")
        assert.are.same("%7l", vim.wo[new_win].statuscolumn, ":new window should get captured statuscolumn")

        vim.wo.signcolumn = saved_sc
        vim.wo.foldcolumn = saved_fc
        vim.wo.statuscolumn = saved_scol
    end)

    it("close_cling_window is idempotent when called with no cling window open", function()
        -- should not error
        core.close_cling_window()
        core.close_cling_window()
        -- reaching here without error is success
        assert.is_nil(core.cling_window)
        assert.is_nil(core.cling_buffer)
    end)

    it("captures columns when cling opens in a new tab", function()
        local saved_sc = vim.wo.signcolumn
        local saved_fc = vim.wo.foldcolumn
        local saved_scol = vim.wo.statuscolumn

        vim.wo.signcolumn = "auto:5"
        vim.wo.foldcolumn = "5"
        vim.wo.statuscolumn = "%5l"

        local original_win = vim.api.nvim_get_current_win()

        -- open cling in a new tab
        core.executor("echo tabtest", "/tmp", {
            smods = { vertical = false, tab = 0, split = "" },
        })

        -- cling window in the new tab should be zeroed
        assert.are.same("", vim.wo[core.cling_window].statuscolumn)
        assert.are.same("no", vim.wo[core.cling_window].signcolumn)
        assert.are.same("0", vim.wo[core.cling_window].foldcolumn)

        -- go back to original window and create a split there
        vim.api.nvim_set_current_win(original_win)
        vim.cmd "vsplit"
        local new_win = vim.api.nvim_get_current_win()

        -- new window in original tab should get captured values
        assert.are.same("auto:5", vim.wo[new_win].signcolumn, "split in original tab should get captured signcolumn")
        assert.are.same("5", vim.wo[new_win].foldcolumn, "split in original tab should get captured foldcolumn")
        assert.are.same("%5l", vim.wo[new_win].statuscolumn, "split in original tab should get captured statuscolumn")

        vim.wo.signcolumn = saved_sc
        vim.wo.foldcolumn = saved_fc
        vim.wo.statuscolumn = saved_scol
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

    describe("jump", function()
        it("registers <CR> keymap on the output buffer", function()
            core.executor("echo hello", "/tmp")
            local keymaps = vim.api.nvim_buf_get_keymap(core.cling_buffer, "n")
            local found_cr = false
            for _, km in ipairs(keymaps) do
                if km.lhs == "<CR>" then
                    found_cr = true
                    break
                end
            end
            assert.is_true(found_cr, "<CR> keymap should be registered on the buffer")
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
