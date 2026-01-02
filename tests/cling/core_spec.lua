local core = require "cling.core"

describe("core", function()
    before_each(function()
        -- Reset state
        if core.cling_window and vim.api.nvim_win_is_valid(core.cling_window) then
            vim.api.nvim_win_close(core.cling_window, true)
        end

        -- Force delete any buffer named [Cling] or [Cling] (1) etc just in case
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

            -- Restore
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
end)
