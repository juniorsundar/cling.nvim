local parser = require "cling.parser"

describe("parser", function()
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
            local result = parser.parse_help(content)

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
            local result = parser.parse_help(content)
            assert.are.same({ "--flag1", "--flag2" }, result.flags)
            assert.is_not_nil(result.subcommands["cmd1"])
        end)
    end)

    describe("parse_bash", function()
        it("detects file completion type", function()
            local content = [[
            compgen -f
        ]]
            local result = parser.parse_bash("foo", content)
            assert.are.same("file", result.completion_type)
        end)

        it("detects directory completion type", function()
            local content = [[
            compgen -d
        ]]
            local result = parser.parse_bash("foo", content)
            assert.are.same("dir", result.completion_type)
        end)
    end)
end)
