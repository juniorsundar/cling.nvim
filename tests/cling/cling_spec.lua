local cling = require "cling"
local core = require "cling.core"
local stub = require "luassert.stub"

describe("cling", function()
    describe("setup", function()
        it("merges config", function()
            cling.setup {
                wrappers = {
                    { binary = "foo", command = "Foo" },
                },
            }

            assert.is_not_nil(cling.config.wrappers)
            assert.are.same(1, #cling.config.wrappers)
            assert.are.same("foo", cling.config.wrappers[1].binary)
        end)
    end)

    describe("wrapper cwd resolution", function()
        local executor_stub
        local getcwd_stub

        before_each(function()
            executor_stub = stub(core, "executor")
            getcwd_stub = stub(vim.fn, "getcwd", function()
                return "/default/cwd"
            end)
        end)

        after_each(function()
            executor_stub:revert()
            getcwd_stub:revert()

            pcall(vim.api.nvim_del_user_command, "CwdFnWrapper")
            pcall(vim.api.nvim_del_user_command, "CwdStrWrapper")
            pcall(vim.api.nvim_del_user_command, "CwdNilWrapper")
        end)

        it("uses cwd function result when wrapper.cwd is a function", function()
            cling.setup {
                wrappers = {
                    {
                        binary = "echo",
                        command = "CwdFnWrapper",
                        cwd = function()
                            return "/from/function"
                        end,
                    },
                },
            }

            vim.cmd "CwdFnWrapper"

            assert.stub(executor_stub).was_called()
            local call_args = executor_stub.calls[1]
            assert.are.same("/from/function", call_args.refs[2])
        end)

        it("uses cwd string directly when wrapper.cwd is a string", function()
            cling.setup {
                wrappers = {
                    {
                        binary = "echo",
                        command = "CwdStrWrapper",
                        cwd = "/static/path",
                    },
                },
            }

            vim.cmd "CwdStrWrapper"

            assert.stub(executor_stub).was_called()
            local call_args = executor_stub.calls[1]
            assert.are.same("/static/path", call_args.refs[2])
        end)

        it("falls back to vim.fn.getcwd() when wrapper.cwd is nil", function()
            cling.setup {
                wrappers = {
                    {
                        binary = "echo",
                        command = "CwdNilWrapper",
                    },
                },
            }

            vim.cmd "CwdNilWrapper"

            assert.stub(executor_stub).was_called()
            local call_args = executor_stub.calls[1]
            assert.are.same("/default/cwd", call_args.refs[2])
        end)
    end)

    describe("wrapper no_history", function()
        local executor_stub
        local getcwd_stub

        before_each(function()
            executor_stub = stub(core, "executor")
            getcwd_stub = stub(vim.fn, "getcwd", function()
                return "/default/cwd"
            end)
        end)

        after_each(function()
            executor_stub:revert()
            getcwd_stub:revert()
            pcall(vim.api.nvim_del_user_command, "NoHistoryWrapper")
            pcall(vim.api.nvim_del_user_command, "HistoryOptInWrapper")
        end)

        it("passes no_history = true by default for wrapper commands", function()
            cling.setup {
                wrappers = {
                    { binary = "echo", command = "NoHistoryWrapper" },
                },
            }

            vim.cmd "NoHistoryWrapper"

            assert.stub(executor_stub).was_called()
            local call_args = executor_stub.calls[1]
            assert.is_true(call_args.refs[3].no_history)
        end)

        it("passes no_history = false when wrapper sets no_history = false", function()
            cling.setup {
                wrappers = {
                    { binary = "echo", command = "HistoryOptInWrapper", no_history = false },
                },
            }

            vim.cmd "HistoryOptInWrapper"

            assert.stub(executor_stub).was_called()
            local call_args = executor_stub.calls[1]
            assert.is_false(call_args.refs[3].no_history)
        end)
    end)

    describe("wrapper on_close forwarding", function()
        local executor_stub
        local getcwd_stub

        before_each(function()
            executor_stub = stub(core, "executor")
            getcwd_stub = stub(vim.fn, "getcwd", function()
                return "/default/cwd"
            end)
        end)

        after_each(function()
            executor_stub:revert()
            getcwd_stub:revert()
            pcall(vim.api.nvim_del_user_command, "OnCloseWrapper")
            pcall(vim.api.nvim_del_user_command, "NoOnCloseWrapper")
        end)

        it("forwards on_close to executor opts when wrapper defines on_close", function()
            local my_on_close = function(_buf) end
            cling.setup {
                wrappers = {
                    {
                        binary = "echo",
                        command = "OnCloseWrapper",
                        on_close = my_on_close,
                    },
                },
            }

            vim.cmd "OnCloseWrapper"

            assert.stub(executor_stub).was_called()
            local call_args = executor_stub.calls[1]
            assert.are.same(my_on_close, call_args.refs[3].on_close)
        end)

        it("passes nil on_close to executor opts when wrapper does not define on_close", function()
            cling.setup {
                wrappers = {
                    { binary = "echo", command = "NoOnCloseWrapper" },
                },
            }

            vim.cmd "NoOnCloseWrapper"

            assert.stub(executor_stub).was_called()
            local call_args = executor_stub.calls[1]
            assert.is_nil(call_args.refs[3].on_close)
        end)

        it("calls binary function to resolve cmd when wrapper.binary is a function", function()
            local called = false
            cling.setup {
                wrappers = {
                    {
                        binary = function()
                            called = true
                            return "echo"
                        end,
                        command = "OnCloseWrapper",
                    },
                },
            }

            vim.cmd "OnCloseWrapper"

            assert.stub(executor_stub).was_called()
            assert.is_true(called, "binary function should have been called")
        end)
    end)
end)
