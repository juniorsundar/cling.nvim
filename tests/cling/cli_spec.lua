local cling = require "cling"
local core = require "cling.core"
local mock = require "luassert.mock"
local stub = require "luassert.stub"

describe("cling cli", function()
    local input_stub
    local executor_stub
    local notify_stub
    local getcwd_stub

    before_each(function()
        core.last_cmd = nil
        core.last_cwd = nil
        core.last_env = nil

        executor_stub = stub(core, "executor")

        notify_stub = stub(vim, "notify")

        getcwd_stub = stub(vim.fn, "getcwd", function()
            return "/default/cwd"
        end)

        input_stub = stub(vim.fn, "input")
    end)

    after_each(function()
        input_stub:revert()
        executor_stub:revert()
        notify_stub:revert()
        getcwd_stub:revert()
    end)

    it("runs command interactively with manual input", function()
        local call_count = 0
        input_stub.invokes(function(...)
            call_count = call_count + 1
            if call_count == 1 then
                return "echo test"
            end
            if call_count == 2 then
                return "/custom/cwd"
            end
            return ""
        end)

        cling.on_cli_command { fargs = {} }

        assert.stub(executor_stub).was_called_with("echo test", "/custom/cwd")
    end)

    it("cancels interactive command if input is empty", function()
        input_stub.returns ""

        cling.on_cli_command { fargs = {} }

        assert.stub(executor_stub).was_not_called()
    end)

    it("runs command with -- args", function()
        cling.on_cli_command { fargs = { "--", "ls", "-la" } }
        assert.stub(executor_stub).was_called_with("ls -la", "/default/cwd")
    end)

    it("handles with-env flow", function()
        local call_count = 0
        input_stub.invokes(function(...)
            call_count = call_count + 1
            if call_count == 1 then
                return ".env.prod"
            end
            if call_count == 2 then
                return "build"
            end
            if call_count == 3 then
                return "/src"
            end
            return ""
        end)

        cling.on_cli_command { fargs = { "with-env" } }

        assert.equals(".env.prod", core.last_env)
        assert.stub(executor_stub).was_called_with("build", "/src")
    end)

    it("handles last command", function()
        core.last_cmd = "previous cmd"
        core.last_cwd = "/previous/cwd"

        cling.on_cli_command { fargs = { "last" } }

        assert.stub(executor_stub).was_called_with("previous cmd", "/previous/cwd")
    end)

    it("warns if no last command", function()
        core.last_cmd = nil
        cling.on_cli_command { fargs = { "last" } }

        assert.stub(notify_stub).was_called()
        assert.stub(executor_stub).was_not_called()
    end)

    it("handles defaults in interactive mode", function()
        core.last_cmd = "last_cmd"
        core.last_cwd = "/last/cwd"

        input_stub.invokes(function(prompt, default)
            return default
        end)

        cling.on_cli_command { fargs = {} }

        assert.stub(executor_stub).was_called_with("last_cmd", "/last/cwd")
    end)
end)
