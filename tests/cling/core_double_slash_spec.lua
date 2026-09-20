local core = require "cling.core"
local history = require "cling.history"

describe("core executor with '//' inside the command", function()
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

        while vim.fn.tabpagenr "$" > 1 do
            vim.cmd "tabclose $"
        end
    end)

    it("does not error when the command contains a URL-style '//' sequence", function()
        local ok, err = pcall(
            core.executor,
            "echo wget https://go.dev/dl/go1.27.1.linux-amd64.tar.gz",
            "/tmp",
            { no_history = true, no_cwd_history = true }
        )

        assert.is_true(ok, "executor must not error on '//' in command — got: " .. tostring(err))
        assert.is_not_nil(core.cling_buffer)
        assert.is_true(vim.api.nvim_buf_is_valid(core.cling_buffer))
        assert.are.same("terminal", vim.bo[core.cling_buffer].buftype)
    end)
end)
