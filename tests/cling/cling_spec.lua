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
end)
