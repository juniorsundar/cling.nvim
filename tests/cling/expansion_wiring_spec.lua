local cling = require "cling"
local core = require "cling.core"
local history = require "cling.history"
local match = require "luassert.match"
local stub = require "luassert.stub"

describe("expansion wiring", function()
    local FAKE_FILE = vim.fs.joinpath(vim.fn.stdpath "run", "cling_expand_fake_target.txt")
    local input_stub
    local cmd_stub
    local notify_stub
    local captured_term_cmd

    local function fake_current_file()
        return vim.fn.fnamemodify(FAKE_FILE, ":p")
    end

    before_each(function()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_get_name(buf):match "%[Cling%]" then
                vim.api.nvim_buf_delete(buf, { force = true })
            end
        end

        vim.fn.writefile({ "fake content" }, FAKE_FILE)

        -- Open the fake file in the current window so vim's `%` resolves to it.
        vim.cmd "enew"
        vim.cmd("edit " .. FAKE_FILE)

        core.last_cmd = nil
        core.last_cwd = nil
        core.last_env = nil
        core.last_smods = nil
        core.cling_window = nil
        core.cling_buffer = nil
        history.clear "/tmp"
        history.clear "/default/cwd"

        notify_stub = stub(vim, "notify")

        captured_term_cmd = nil
        cmd_stub = stub(vim, "cmd", function(command)
            if type(command) == "string" and command:find "term://" then
                captured_term_cmd = command
            end
        end)

        input_stub = stub(vim.fn, "input")
    end)

    after_each(function()
        input_stub:revert()
        cmd_stub:revert()
        notify_stub:revert()

        history.clear "/tmp"
        history.clear "/default/cwd"
        os.remove(FAKE_FILE)

        core.last_cmd = nil
        core.last_cwd = nil
        core.last_env = nil
        core.last_smods = nil
        core.cling_window = nil
        core.cling_buffer = nil
    end)

    --- Asserts the shell receives an expanded line while last_cmd stays raw.
    --- Vim shellescapes the terminal command, so escape backslashes are stripped
    --- before matching the full expected phrase in order.
    local function assert_expanded_reaches_shell(expected_expanded)
        assert.truthy(captured_term_cmd, "executor should have issued a term:// command")
        local unescaped = captured_term_cmd:gsub("\\", "")
        assert.truthy(
            unescaped:find(expected_expanded, 1, true),
            "shell should receive '" .. expected_expanded .. "', got: " .. captured_term_cmd
        )
    end

    it("interactive prompt expands @% against the execution CWD after both prompts resolve", function()
        local call_count = 0
        input_stub.invokes(function(...)
            call_count = call_count + 1
            if call_count == 1 then
                return "cat @%"
            end
            if call_count == 2 then
                return "/tmp"
            end
            return ""
        end)

        cling.on_cli_command { fargs = {} }

        assert_expanded_reaches_shell("cat " .. fake_current_file())
        -- History keeps the raw typed line.
        assert.equals("cat @%", core.last_cmd)
        assert.equals("cat @%", history.get("/tmp")[#history.get "/tmp"])
    end)

    it("-- passthrough expands @% with execution CWD = current working directory", function()
        cling.on_cli_command { fargs = { "--", "cat", "@%" } }

        assert_expanded_reaches_shell("cat " .. fake_current_file())
        assert.equals("cat @%", core.last_cmd)
    end)

    it(":Cling last re-expands the stored raw command at execution time", function()
        core.last_cmd = "cat @%"
        core.last_cwd = "/tmp"

        input_stub.returns ""

        cling.on_cli_command { fargs = { "last" } }

        assert_expanded_reaches_shell("cat " .. fake_current_file())
        assert.equals("cat @%", core.last_cmd)
    end)

    it("with-env flow expands marked tokens and prefixes .env downstream of expansion", function()
        local call_count = 0
        input_stub.invokes(function(...)
            call_count = call_count + 1
            if call_count == 1 then
                return "/tmp/fake.env"
            end
            if call_count == 2 then
                return "cat @%"
            end
            if call_count == 3 then
                return "/tmp"
            end
            return ""
        end)

        cling.on_cli_command { fargs = { "with-env" } }

        assert_expanded_reaches_shell(". /tmp/fake.env && cat " .. fake_current_file())
        assert.equals("cat @%", core.last_cmd)
    end)

    it("-- passthrough expands @<cword> from the window under the cursor", function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "my_cursor_word here" })
        vim.cmd "1"
        vim.cmd "normal! 1|"

        cling.on_cli_command { fargs = { "--", "grep", "@<cword>", "/tmp" } }

        assert_expanded_reaches_shell "grep my_cursor_word /tmp"
    end)

    it("-- passthrough expands @#N to buffer N's file path", function()
        local alt = FAKE_FILE .. ".alt"
        vim.fn.writefile({ "alt" }, alt)
        -- vim.cmd is stubbed in this spec; use nvim_command to actually switch buffers.
        vim.api.nvim_command("edit " .. alt)
        local alt_bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_command("edit " .. FAKE_FILE)

        cling.on_cli_command { fargs = { "--", "cat", "@#" .. alt_bufnr } }

        assert_expanded_reaches_shell("cat " .. vim.fn.fnamemodify(alt, ":p"))
        vim.api.nvim_command "enew" -- leave the alt buffer so deleting its file is safe
        os.remove(alt)
    end)

    it("-- passthrough expands @<cWORD> preserving punctuation via the real provider", function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo.bar baz" })
        vim.cmd "1"
        vim.cmd "normal! 1|"

        cling.on_cli_command { fargs = { "--", "test", "@<cWORD>" } }

        assert_expanded_reaches_shell "test foo.bar"
    end)

    it("-- passthrough expands @<cfile> from the text under the cursor", function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "see src/main.lua here" })
        -- vim.cmd is stubbed; set the cursor via API (0-indexed col onto "src").
        vim.api.nvim_win_set_cursor(0, { 1, 4 })

        cling.on_cli_command { fargs = { "--", "cat", "@<cfile>" } }

        local expected = vim.fn.fnamemodify(vim.fs.joinpath(vim.fn.getcwd(), "src/main.lua"), ":p")
        assert_expanded_reaches_shell("cat " .. expected)
    end)

    it("-- passthrough expands @# to the alternate file's path", function()
        local alt = FAKE_FILE .. ".alt"
        vim.fn.writefile({ "alt" }, alt)
        -- vim.cmd is stubbed in this spec; use nvim_command to actually switch buffers.
        vim.api.nvim_command("edit " .. alt)
        vim.api.nvim_command("edit " .. FAKE_FILE)

        cling.on_cli_command { fargs = { "--", "cat", "@#" } }

        assert_expanded_reaches_shell("cat " .. vim.fn.fnamemodify(alt, ":p"))
        vim.api.nvim_command "enew" -- leave the alt buffer so deleting its file is safe
        os.remove(alt)
    end)

    it("wrapper commands do NOT expand marked tokens", function()
        input_stub.returns ""

        -- Wrappers call core.executor directly without opts.expand.
        core.executor("echo @%", "/tmp", { no_history = true })

        -- The marker must survive (vim only percent-escapes it); no expansion.
        assert.truthy(captured_term_cmd:find("echo\\ @", 1, true))
        assert.falsy(captured_term_cmd:find(fake_current_file(), 1, true))
    end)
end)
