local command_node = require "cling.command_node"

describe("command_node", function()
    describe("parse_help", function()
        it("parses usage with commands and options", function()
            local content = [[
Usage:
  mytool [command]

Commands:
  start   Start the service
  stop    Stop the service

Options:
  --verbose   Run verbosely
  -v          Short verbose
]]
            local result = command_node.parse_help(content)

            local keys = vim.tbl_keys(result.subcommands)
            table.sort(keys)
            assert.are.same({ "start", "stop" }, keys)
            assert.is_not_nil(result.subcommands["start"])
            assert.is_not_nil(result.subcommands["stop"])

            -- Flags are sorted
            assert.are.same({ "--verbose", "-v" }, result.flags)
        end)

        it("parses usage with different section headers", function()
            local content = [[
Usage: foo

Flags:
  --flag1
  --flag2

Commands:
  cmd1
]]
            local result = command_node.parse_help(content)
            assert.are.same({ "--flag1", "--flag2" }, result.flags)
            assert.is_not_nil(result.subcommands["cmd1"])
        end)
    end)

    describe("new", function()
        it("returns a node with empty flags and subcommands and no completion_type", function()
            local node = command_node.new()

            assert.are.same({}, node.flags)
            assert.are.same({}, node.subcommands)
            assert.is_nil(node.completion_type)
        end)
    end)

    describe("load", function()
        it("returns nil for a nonexistent file", function()
            assert.is_nil(command_node.load "/nonexistent/path/cache.lua")
        end)

        it("returns nil when the file contains invalid Lua", function()
            local path = os.tmpname()
            local f = io.open(path, "w")
            f:write "this is not lua {{{"
            f:close()

            assert.is_nil(command_node.load(path))
            os.remove(path)
        end)

        it("normalizes missing flags and subcommands to empty tables", function()
            local path = os.tmpname()
            local f = io.open(path, "w")
            f:write "return { flags = { '--verbose' } }"
            f:close()

            local node = command_node.load(path)
            os.remove(path)

            assert.are.same({ "--verbose" }, node.flags)
            assert.are.same({}, node.subcommands)
        end)

        it("normalizes missing fields on nested subcommand nodes", function()
            local path = os.tmpname()
            local f = io.open(path, "w")
            f:write "return { subcommands = { run = { flags = { '--fast' } } } }"
            f:close()

            local node = command_node.load(path)
            os.remove(path)

            assert.are.same({}, node.subcommands["run"].subcommands)
        end)

        it("loads a well-formed serialized node unchanged", function()
            local root = command_node.new()
            root.flags = { "--force" }
            root.subcommands["start"] = command_node.new()
            root.subcommands["start"].completion_type = "dir"

            local path = os.tmpname()
            local f = io.open(path, "w")
            f:write("return " .. command_node.serialize(root))
            f:close()

            local node = command_node.load(path)
            os.remove(path)

            assert.are.same(root, node)
        end)
    end)

    describe("serialize", function()
        it("round-trips a tree built with new()", function()
            local root = command_node.new()
            root.flags = { "--verbose", "-v" }
            root.subcommands["start"] = command_node.new()
            root.subcommands["start"].flags = { "--force" }
            root.subcommands["start"].completion_type = "dir"
            root.subcommands["stop"] = command_node.new()

            local chunk = loadstring("return " .. command_node.serialize(root))
            assert.is_not_nil(chunk)
            local restored = chunk()

            assert.are.same(root, restored)
        end)

        it("omits completion_type when nil", function()
            local node = command_node.new()
            local serialized = command_node.serialize(node)

            assert.truthy(serialized:match "completion_type" == nil)
        end)
    end)

    describe("parse_bash", function()
        it("detects file completion type", function()
            local content = [[
            compgen -f
        ]]
            local result = command_node.parse_bash("foo", content)
            assert.are.same("file", result.completion_type)
        end)

        it("detects directory completion type", function()
            local content = [[
            compgen -d
        ]]
            local result = command_node.parse_bash("foo", content)
            assert.are.same("dir", result.completion_type)
        end)
    end)
end)
