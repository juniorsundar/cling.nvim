local nav = require "cling.navigation"

describe("navigation.jump_to", function()
    local tmpfile = "/tmp/cling_jump_target.txt"
    local target_win

    before_each(function()
        local f = io.open(tmpfile, "w")
        f:write "line one\nline two\nline three\nline four\nline five\n"
        f:close()
        target_win = vim.api.nvim_get_current_win()
    end)

    after_each(function()
        os.remove(tmpfile)
        -- return to a scratch buffer so the target window no longer holds the jumped-to file
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
        vim.cmd "enew!"
        -- wipe any buffers still holding the temp file so the next test gets a fresh :edit
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_get_name(b):match "cling_jump" then
                pcall(vim.api.nvim_buf_delete, b, { force = true })
            end
        end
    end)

    it("opens a file at the correct line and column for file:line:col:message", function()
        nav.jump_to(tmpfile .. ":3:2:error: boom", tmpfile, "/tmp", target_win)

        assert.equals(vim.fn.fnamemodify(tmpfile, ":p"), vim.api.nvim_buf_get_name(0))
        assert.equals(3, vim.fn.line ".")
        assert.equals(2, vim.fn.col ".")
    end)

    it("opens a file at the correct line for file:line without column", function()
        nav.jump_to(tmpfile .. ":4", tmpfile, "/tmp", target_win)

        assert.equals(vim.fn.fnamemodify(tmpfile, ":p"), vim.api.nvim_buf_get_name(0))
        assert.equals(4, vim.fn.line ".")
    end)

    it("resolves the file path relative to the provided cwd", function()
        vim.fn.mkdir("/tmp/cling_jump_cwd", "p")
        local rel_file = "/tmp/cling_jump_cwd/rel.txt"
        local f = io.open(rel_file, "w")
        f:write "alpha\nbeta\n"
        f:close()

        nav.jump_to("rel.txt:2", "rel.txt", "/tmp/cling_jump_cwd", target_win)

        assert.equals(vim.fn.fnamemodify(rel_file, ":p"), vim.api.nvim_buf_get_name(0))
        assert.equals(2, vim.fn.line ".")

        os.remove(rel_file)
    end)

    it("falls back to cfile alone when the joined path doesn't exist but cfile does", function()
        -- cfile is absolute; joining with cwd produces a nonexistent path
        nav.jump_to(tmpfile .. ":5", tmpfile, "/definitely/not/a/dir", target_win)

        assert.equals(vim.fn.fnamemodify(tmpfile, ":p"), vim.api.nvim_buf_get_name(0))
        assert.equals(5, vim.fn.line ".")
    end)

    it("silently returns when the file doesn't exist at either path", function()
        local buf_before = vim.api.nvim_get_current_buf()
        local ok = pcall(nav.jump_to, "/no/such/file.txt:1:1:err", "/no/such/file.txt", "/tmp", target_win)

        assert.is_true(ok, "jump_to should not error on missing file")
        assert.equals(buf_before, vim.api.nvim_get_current_buf(), "current buffer should be unchanged")
    end)

    it("notifies when the target window is no longer valid", function()
        local notified = nil
        local orig_notify = vim.notify
        vim.notify = function(msg, level)
            notified = { msg = msg, level = level }
        end

        local dead_win =
            vim.api.nvim_open_win(0, false, { relative = "editor", width = 10, height = 5, row = 0, col = 0 })
        vim.api.nvim_win_close(dead_win, true)

        pcall(nav.jump_to, tmpfile .. ":1:1:err", tmpfile, "/tmp", dead_win)

        vim.notify = orig_notify
        assert.is_not_nil(notified, "should notify about invalid window")
        assert.matches("Original window is no longer valid", notified.msg)
    end)

    it("trims the line to start from the cfile position before parsing", function()
        -- leading text that would confuse the efm if not trimmed first
        local line = "note: something 12:34 unrelated /tmp/cling_jump_target.txt:2:1:trimmed"
        nav.jump_to(line, tmpfile, "/tmp", target_win)

        assert.equals(vim.fn.fnamemodify(tmpfile, ":p"), vim.api.nvim_buf_get_name(0))
        assert.equals(2, vim.fn.line ".")
        assert.equals(1, vim.fn.col ".")
    end)
end)

describe("navigation.export", function()
    after_each(function()
        os.remove "/tmp/cling_nav_test.log"
    end)

    it("writes buffer content with metadata footer to a file", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "build output line 1",
            "error: something failed",
        })

        nav.export(buf, "make test", "/tmp", "/tmp/cling_nav_test.log")

        local lines = vim.fn.readfile "/tmp/cling_nav_test.log"
        assert.is_not_nil(lines, "exported file should exist")

        assert.equals("build output line 1", lines[1])
        assert.equals("error: something failed", lines[2])

        local found_cmd = false
        local found_cwd = false
        local found_ts = false
        local found_vim = false

        for _, line in ipairs(lines) do
            if line == "-- Command: make test" then
                found_cmd = true
            end
            if line == "-- CWD: /tmp" then
                found_cwd = true
            end
            if line:match "^-- Timestamp: %d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$" then
                found_ts = true
            end
            if line == "-- vim: ft=log" then
                found_vim = true
            end
        end

        assert.is_true(found_cmd, "metadata should contain Command line")
        assert.is_true(found_cwd, "metadata should contain CWD line")
        assert.is_true(found_ts, "metadata should contain ISO 8601 Timestamp line")
        assert.is_true(found_vim, "metadata should contain vim modeline")
    end)

    it("preserves ANSI escape codes", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "\27[31mred text\27[0m",
            "\27[1;32mbold green\27[0m",
            "plain line",
        })

        nav.export(buf, "echo hello", "/tmp", "/tmp/cling_nav_test.log")

        local lines = vim.fn.readfile "/tmp/cling_nav_test.log"
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
    end)

    it("strips trailing empty lines before writing", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "real output",
            "",
            "",
            "",
        })

        nav.export(buf, "make test", "/tmp", "/tmp/cling_nav_test.log")

        local lines = vim.fn.readfile "/tmp/cling_nav_test.log"
        assert.is_not_nil(lines, "exported file should exist")

        -- real output, blank separator, 4 footer lines
        assert.equals(6, #lines, "trailing empty lines should be stripped")
        assert.equals("real output", lines[1])
        assert.equals("", lines[2])
        assert.equals("-- Command: make test", lines[3])
    end)
end)
