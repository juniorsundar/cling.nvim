--- @module 'cling.crawlers.help_crawler'
local parser = require "cling.parser"

local M = {}

--- Executes a shell command and captures its standard output.
---
--- @param cmd string The shell command to execute.
--- @return string output The captured stdout content, or an empty string on failure.
local function exec(cmd)
    local handle = io.popen(cmd .. " 2>/dev/null")
    if not handle then
        return ""
    end
    local result = handle:read "*a"
    handle:close()
    return result or ""
end

--- Recursively crawls a CLI's help output to build a structured completion tree.
---
--- @param binary string The base binary name.
--- @param args string[] The sequence of subcommands reached so far.
--- @param help_cmd string The flag used to trigger help (e.g., "--help").
--- @param depth integer The current recursion depth.
--- @return cling.CommandNode node The constructed command node for this level.
local function crawl(binary, args, help_cmd, depth)
    -- Depth limit to prevent infinite recursion and excessive execution time.
    if depth > 4 then
        return { flags = {}, subcommands = {} }
    end

    local cmd_parts = { binary }
    for _, a in ipairs(args) do
        table.insert(cmd_parts, a)
    end
    table.insert(cmd_parts, help_cmd)

    local cmd_str = table.concat(cmd_parts, " ")

    if depth == 0 then
        vim.notify("Generating completions for " .. binary .. "...", vim.log.levels.INFO)
    end

    local content = exec(cmd_str)
    local node = parser.parse_help(content)

    for sub, _ in pairs(node.subcommands) do
        local new_args = { unpack(args) }
        table.insert(new_args, sub)

        node.subcommands[sub] = crawl(binary, new_args, help_cmd, depth + 1)
    end

    return node
end

--- Generates a complete completion tree by recursively crawling a binary's help system.
---
--- @param binary string The name of the binary to crawl.
--- @param help_cmd string The help flag to use (e.g., "--help").
--- @return cling.CommandNode completions The fully populated completion tree.
function M.generate(binary, help_cmd)
    return crawl(binary, {}, help_cmd, 0)
end

return M
