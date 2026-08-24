local history = require "cling.history"
local core = require "cling.core"

local history_base_dir = vim.fn.stdpath "data" .. "/cling/history"
local tmp_cwd = "/tmp/cling-history-spec-" .. vim.fn.getpid()
local var_cwd = "/var/cling-history-spec-" .. vim.fn.getpid()
local test_cwds = { tmp_cwd, var_cwd }

local function history_path(cwd)
    local escaped = cwd:gsub("[/\\:%%]", "_")
    return history_base_dir .. "/" .. escaped .. ".lua"
end

local function cleanup()
    for _, cwd in ipairs(test_cwds) do
        local path = history_path(cwd)
        if vim.uv.fs_stat(path) then
            os.remove(path)
        end
    end
end

describe("history", function()
    before_each(function()
        for _, cwd in ipairs(test_cwds) do
            history.clear(cwd)
        end
        cleanup()

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
        while vim.fn.tabpagenr "$" > 1 do
            vim.cmd "tabclose $"
        end
    end)

    after_each(function()
        for _, cwd in ipairs(test_cwds) do
            history.clear(cwd)
        end
        cleanup()
    end)

    describe("add", function()
        it("adds a command to the history list for a given cwd", function()
            history.add(tmp_cwd, "echo hello")
            local h = history.get(tmp_cwd)
            assert.is_not_nil(h)
            assert.are.same({ "echo hello" }, h)
        end)

        it("appends commands in order (most recent last)", function()
            history.add(tmp_cwd, "echo first")
            history.add(tmp_cwd, "echo second")
            local h = history.get(tmp_cwd)
            assert.are.same({ "echo first", "echo second" }, h)
        end)

        it("does not mix histories between different cwds", function()
            history.add(tmp_cwd, "echo tmp")
            history.add(var_cwd, "echo var")
            assert.are.same({ "echo tmp" }, history.get(tmp_cwd))
            assert.are.same({ "echo var" }, history.get(var_cwd))
        end)
    end)

    describe("get", function()
        it("returns an empty table when no history exists for the cwd", function()
            local h = history.get(tmp_cwd)
            assert.are.same({}, h)
        end)

        it("returns all added commands for the cwd", function()
            history.add(tmp_cwd, "ls")
            history.add(tmp_cwd, "pwd")
            local h = history.get(tmp_cwd)
            assert.are.same({ "ls", "pwd" }, h)
        end)
    end)

    describe("save", function()
        it("persists the history for a cwd to the data dir", function()
            history.add(tmp_cwd, "ls -la")
            history.save(tmp_cwd)

            local path = history_path(tmp_cwd)
            local stat = vim.uv.fs_stat(path)
            assert.is_not_nil(stat, "history file should exist after save")
        end)

        it("creates the base directory if it does not exist", function()
            history.add(tmp_cwd, "make")
            history.save(tmp_cwd)
            local stat = vim.uv.fs_stat(history_base_dir)
            assert.is_not_nil(stat, "history base dir should exist after save")
        end)
    end)

    describe("load", function()
        it("returns an empty table when no file exists for the cwd", function()
            local h = history.load(tmp_cwd)
            assert.are.same({}, h)
        end)

        it("loads history previously saved to disk", function()
            history.add(tmp_cwd, "cargo build")
            history.add(tmp_cwd, "cargo test")
            history.save(tmp_cwd)

            history.clear(tmp_cwd)

            local h = history.load(tmp_cwd)
            assert.are.same({ "cargo build", "cargo test" }, h)
        end)

        it("populates in-memory state after loading", function()
            history.add(tmp_cwd, "make check")
            history.save(tmp_cwd)
            history.clear(tmp_cwd)

            history.load(tmp_cwd)

            local h = history.get(tmp_cwd)
            assert.are.same({ "make check" }, h)
        end)
    end)

    describe("clear", function()
        it("clears in-memory history for a cwd", function()
            history.add(tmp_cwd, "ls")
            history.clear(tmp_cwd)
            assert.are.same({}, history.get(tmp_cwd))
        end)

        it("does not affect history for other cwds", function()
            history.add(tmp_cwd, "ls")
            history.add(var_cwd, "pwd")
            history.clear(tmp_cwd)
            assert.are.same({}, history.get(tmp_cwd))
            assert.are.same({ "pwd" }, history.get(var_cwd))
        end)

        it("does not remove the file from disk", function()
            history.add(tmp_cwd, "ls")
            history.save(tmp_cwd)
            history.clear(tmp_cwd)
            local stat = vim.uv.fs_stat(history_path(tmp_cwd))
            assert.is_not_nil(stat, "disk file should still exist after in-memory clear")
        end)
    end)

    describe("executor integration", function()
        it("adds the command to the cwd history after execution", function()
            core.executor("ls", tmp_cwd)
            local h = history.get(tmp_cwd)
            local found = false
            for _, cmd in ipairs(h) do
                if cmd == "ls" then
                    found = true
                    break
                end
            end
            assert.is_true(found, "history for /tmp should contain 'ls' after executor call")
        end)

        it("does NOT add to history when no_history is true", function()
            history.clear(tmp_cwd)
            core.executor("ls", tmp_cwd, { no_history = true })
            local h = history.get(tmp_cwd)
            local found = false
            for _, cmd in ipairs(h) do
                if cmd == "ls" then
                    found = true
                    break
                end
            end
            assert.is_false(found, "history should NOT contain 'ls' when no_history=true")
        end)
    end)

    describe("deduplication", function()
        it("does not create duplicate entries when the same cmd is added twice", function()
            history.add(tmp_cwd, "make")
            history.add(tmp_cwd, "make")
            local h = history.get(tmp_cwd)
            assert.are.same(1, #h, "duplicate entries should be collapsed to one")
        end)

        it("moves the re-added command to the end of the list", function()
            history.add(tmp_cwd, "make")
            history.add(tmp_cwd, "ninja")
            history.add(tmp_cwd, "make") -- re-add first command
            local h = history.get(tmp_cwd)
            assert.are.same({ "ninja", "make" }, h)
        end)
    end)

    describe("max size", function()
        it("does not exceed the default cap of 100 entries", function()
            for i = 1, 110 do
                history.add(tmp_cwd, "cmd" .. i)
            end
            local h = history.get(tmp_cwd)
            assert.is_true(#h <= 100, "history should be capped at 100 entries, got " .. #h)
        end)

        it("evicts the oldest entry when cap is exceeded", function()
            for i = 1, 101 do
                history.add(tmp_cwd, "cmd" .. i)
            end
            local h = history.get(tmp_cwd)
            assert.are.same("cmd2", h[1], "oldest entry should be evicted when cap is exceeded")
        end)

        it("respects a custom max size when provided", function()
            for i = 1, 10 do
                history.add(tmp_cwd, "cmd" .. i, { max_size = 5 })
            end
            local h = history.get(tmp_cwd)
            assert.is_true(#h <= 5, "history should be capped at custom max of 5, got " .. #h)
        end)
    end)

    describe("round-trip persistence", function()
        it("save then load returns the identical history list", function()
            local cmds = { "echo a", "echo b", "echo c" }
            for _, cmd in ipairs(cmds) do
                history.add(tmp_cwd, cmd)
            end
            history.save(tmp_cwd)
            history.clear(tmp_cwd)
            local loaded = history.load(tmp_cwd)
            assert.are.same(cmds, loaded)
        end)

        it("round-trips an empty history without errors", function()
            history.save(tmp_cwd)
            history.clear(tmp_cwd)
            local loaded = history.load(tmp_cwd)
            assert.are.same({}, loaded)
        end)

        it("overwrites stale data on disk when saved again", function()
            history.add(tmp_cwd, "old-cmd")
            history.save(tmp_cwd)

            history.clear(tmp_cwd)
            history.add(tmp_cwd, "new-cmd")
            history.save(tmp_cwd)

            history.clear(tmp_cwd)
            local loaded = history.load(tmp_cwd)
            assert.are.same({ "new-cmd" }, loaded)
        end)
    end)

    describe("no_cwd_history executor opt", function()
        it("skips history.add and history.save when no_cwd_history is true", function()
            core.executor("ls", tmp_cwd, { no_cwd_history = true })
            local h = history.get(tmp_cwd)
            local found = false
            for _, cmd in ipairs(h) do
                if cmd == "ls" then
                    found = true
                    break
                end
            end
            assert.is_false(found, "history should NOT contain 'ls' when no_cwd_history=true")
        end)

        it("still updates last_cmd/last_cwd when no_cwd_history is true", function()
            core.executor("ls", tmp_cwd, { no_cwd_history = true })
            assert.are.same("ls", core.last_cmd)
            assert.are.same(tmp_cwd, core.last_cwd)
        end)

        it("records history normally when no_cwd_history is false", function()
            core.executor("ls", tmp_cwd, { no_cwd_history = false })
            local h = history.get(tmp_cwd)
            local found = false
            for _, cmd in ipairs(h) do
                if cmd == "ls" then
                    found = true
                    break
                end
            end
            assert.is_true(found, "history should contain 'ls' when no_cwd_history=false")
        end)

        it("records history normally when no_cwd_history is omitted", function()
            core.executor("pwd", tmp_cwd)
            local h = history.get(tmp_cwd)
            local found = false
            for _, cmd in ipairs(h) do
                if cmd == "pwd" then
                    found = true
                    break
                end
            end
            assert.is_true(found, "history should contain 'pwd' when no_cwd_history is omitted")
        end)
    end)
end)
