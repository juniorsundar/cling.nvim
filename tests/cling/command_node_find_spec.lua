local assert = require "luassert"
local command_node = require "cling.command_node"

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

--- Mock filesystem completer recording its calls.
--- @param results string[]
--- @return fun(arglead: string, ctype: string): string[], table call_log
local function mock_completer(results)
    local calls = {}
    local fn = function(arglead, completion_type)
        table.insert(calls, { arglead = arglead, completion_type = completion_type })
        return results
    end
    return fn, calls
end

describe("command_node.find", function()
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
            local matches = command_node.find(root, { "commit" }, "commit", {})
            -- Only the root's subcommand name matches; --amend (from inside
            -- "commit") proves no descent happened.
            assert.are.same({ "commit" }, matches)
        end)

        it("stays at current node on unknown arg", function()
            local root = build_node {
                flags = { "--verbose" },
                subcommands = {
                    add = build_node { flags = { "--dry-run" } },
                },
            }
            local matches = command_node.find(root, { "bogus" }, "", {})
            assert.are.same({ "--verbose", "add" }, matches)
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
            local matches = command_node.find(root, { "add", "add" }, "add", {})
            assert.are.same({ "add" }, matches)
        end)
    end)

    describe("candidate collection", function()
        it("collects subcommand names from the current node", function()
            local root = build_node {
                subcommands = {
                    commit = build_node {},
                    add = build_node {},
                },
            }
            local matches = command_node.find(root, {}, "", {})
            assert.are.same({ "add", "commit" }, matches)
        end)

        it("collects flags from the current node", function()
            local root = build_node { flags = { "-f", "--force" } }
            local matches = command_node.find(root, {}, "", {})
            assert.are.same({ "--force", "-f" }, matches)
        end)

        it("collects filesystem candidates when completion_type set and completer returns", function()
            local completer = mock_completer { "src/", "tests/" }
            local root = build_node { completion_type = "dir" }
            local matches = command_node.find(root, {}, "", { filesystem_completer = completer })
            assert.are.same({ "src/", "tests/" }, matches)
        end)

        it("collects no filesystem candidates when completion_type absent", function()
            local completer = mock_completer { "src/" }
            local root = build_node {}
            local matches = command_node.find(root, {}, "", { filesystem_completer = completer })
            assert.are.same({}, matches)
        end)

        it("filters candidates by arglead prefix", function()
            local root = build_node {
                flags = { "--force", "--file" },
                subcommands = { fetch = build_node {} },
            }
            local matches = command_node.find(root, {}, "--f", {})
            assert.are.same({ "--file", "--force" }, matches)
        end)

        it("sorts candidates before returning", function()
            local root = build_node {
                flags = { "--zzz" },
                subcommands = { aaa = build_node {} },
            }
            local matches = command_node.find(root, {}, "", {})
            assert.are.same({ "--zzz", "aaa" }, matches)
        end)
    end)

    describe("filesystem_completer injection", function()
        it("is called with arglead and completion_type; vim.fn.getcompletion not used when provided", function()
            local calls
            local completer
            completer, calls = mock_completer { "Makefile" }
            local root = build_node { completion_type = "file" }

            -- Guard: if find() fell back to vim.fn.getcompletion instead of
            -- calling the mock, the real filesystem would be consulted and
            -- calls would stay empty. Assert on the mock's call log instead.
            local original_getcompletion = vim.fn.getcompletion
            local getcompletion_called = false
            vim.fn.getcompletion = function()
                getcompletion_called = true
                return {}
            end

            local matches = command_node.find(root, { "sub" }, "Ma", { filesystem_completer = completer })

            vim.fn.getcompletion = original_getcompletion

            assert.are.same(1, #calls)
            assert.are.equal("Ma", calls[1].arglead)
            assert.are.equal("file", calls[1].completion_type)
            assert.False(getcompletion_called)
            assert.are.same({ "Makefile" }, matches)
        end)

        it("defaults to vim.fn.getcompletion when not provided", function()
            local root = build_node { completion_type = "file" }
            local original = vim.fn.getcompletion
            local received = nil
            vim.fn.getcompletion = function(arglead, ctype)
                received = { arglead = arglead, ctype = ctype }
                return { "README.md" }
            end

            local ok, matches = pcall(command_node.find, root, {}, "REA", {})

            vim.fn.getcompletion = original
            assert.True(ok)
            assert.are.same({ arglead = "REA", ctype = "file" }, received)
            assert.are.same({ "README.md" }, matches)
        end)
    end)
end)
