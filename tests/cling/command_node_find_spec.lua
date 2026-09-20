local assert = require "luassert"
local command_node = require "cling.command_node"
local stub = require "luassert.stub"

--- Builds a node from shorthand.
--- @param opts table {flags?, subcommands?, completion_type?}
--- @return cling.CommandNode
local function build_node(opts)
    local node = command_node.new()
    node.flags = opts.flags or {}
    node.subcommands = opts.subcommands or {}
    node.completion_type = opts.completion_type
    return node
end

describe("command_node.find", function()
    local getcompletion_stub

    local function stub_getcompletion(results)
        getcompletion_stub = stub(vim.fn, "getcompletion", function()
            return results
        end)
    end

    after_each(function()
        if getcompletion_stub then
            getcompletion_stub:revert()
            getcompletion_stub = nil
        end
    end)

    describe("tree walking", function()
        it("stops descending at arglead", function()
            -- "git commit" completing "commit": the typed token equals the
            -- arglead, so the walk must stop before descending into it.
            local root = build_node {
                subcommands = {
                    add = build_node { flags = { "--dry-run" } },
                    commit = build_node { flags = { "--amend" } },
                },
            }
            local matches = command_node.find(root, { "commit" }, "commit")
            -- Only the root's subcommand name matches; --amend (from inside
            -- "commit") proves no descent happened.
            assert.are.same({ "commit" }, matches)
        end)

        it("descends through known subcommands", function()
            local root = build_node {
                subcommands = {
                    commit = build_node { flags = { "--amend" } },
                },
            }
            local matches = command_node.find(root, { "commit" }, "--a")
            assert.are.same({ "--amend" }, matches)
        end)

        it("stays at the current node on unknown args", function()
            local root = build_node {
                subcommands = {
                    commit = build_node { flags = { "--amend" } },
                    status = build_node {},
                },
            }
            local matches = command_node.find(root, { "bogus" }, "st")
            assert.are.same({ "status" }, matches)
        end)

        it("first occurrence of arglead stops the walk", function()
            local root = build_node {
                subcommands = {
                    add = build_node {
                        subcommands = {
                            deep = build_node { flags = { "--deep-flag" } },
                        },
                    },
                },
            }
            -- "add add" — the first "add" is arglead, so we must NOT descend.
            local matches = command_node.find(root, { "add", "add" }, "add")
            assert.are.same({ "add" }, matches)
        end)
    end)

    describe("candidate collection", function()
        it("collects subcommand names from the current node", function()
            local root = build_node { subcommands = { add = build_node {}, commit = build_node {} } }
            local matches = command_node.find(root, {}, "")
            assert.are.same({ "add", "commit" }, matches)
        end)

        it("collects flags from the current node", function()
            local root = build_node { flags = { "-f", "--force" } }
            local matches = command_node.find(root, {}, "")
            assert.are.same({ "--force", "-f" }, matches)
        end)

        it("collects filesystem candidates when completion_type is set", function()
            stub_getcompletion { "src/", "tests/" }
            local root = build_node { completion_type = "dir" }
            local matches = command_node.find(root, {}, "")
            assert.are.same({ "src/", "tests/" }, matches)
            assert.equals(1, #getcompletion_stub.calls)
        end)

        it("collects no filesystem candidates when completion_type is absent", function()
            stub_getcompletion { "src/" }
            local root = build_node {}
            local matches = command_node.find(root, {}, "")
            assert.are.same({}, matches)
            assert.equals(0, #getcompletion_stub.calls)
        end)

        it("filters candidates by arglead prefix", function()
            local root = build_node {
                flags = { "--force", "--file" },
                subcommands = { fetch = build_node {} },
            }
            local matches = command_node.find(root, {}, "--f")
            assert.are.same({ "--file", "--force" }, matches)
        end)

        it("sorts candidates before returning", function()
            local root = build_node {
                flags = { "--zzz" },
                subcommands = { aaa = build_node {} },
            }
            local matches = command_node.find(root, {}, "")
            assert.are.same({ "--zzz", "aaa" }, matches)
        end)
    end)

    describe("filesystem completion", function()
        it("queries vim.fn.getcompletion with arglead and completion_type", function()
            stub_getcompletion { "Makefile" }
            local root = build_node { completion_type = "file" }

            local matches = command_node.find(root, {}, "Make")

            local call = getcompletion_stub.calls[1]
            assert.are.same("Make", call.refs[1])
            assert.are.same("file", call.refs[2])
            assert.are.same({ "Makefile" }, matches)
        end)
    end)
end)
