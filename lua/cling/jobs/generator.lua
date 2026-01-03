-- lua/cling/jobs/generator.lua

-- Ensure we have enough arguments
if #_G.arg < 5 then
    io.stderr:write "Usage: nvim -l generator.lua <plugin_root> <outfile> <binary> <method> <value>\n"
    os.exit(1)
end

local plugin_root = _G.arg[1]
local outfile = _G.arg[2]
local binary = _G.arg[3]
local method = _G.arg[4]
local value = _G.arg[5]

-- Add plugin root to runtime path
vim.opt.rtp:prepend(plugin_root)

local utils = require "cling.utils"
local parser = require "cling.parser"
local crawler = require "cling.crawlers.help_crawler"
local script_crawler = require "cling.crawlers.completion_script_crawler"

local completions = { flags = {}, subcommands = {} }

local function log(msg)
    io.stdout:write(msg .. "\n")
end

log("Starting generation for " .. binary)

if method == "help_cmd" then
    completions = crawler.generate(binary, value)
elseif method == "completion_file" then
    local file_path = value
    local temp_file = nil

    if value:match "^https?://" then
        temp_file = vim.fn.tempname()
        log("Downloading " .. value)
        vim.fn.system { "curl", "-s", "-o", temp_file, value }
        file_path = temp_file
    else
        file_path = vim.fn.expand(value)
    end

    if vim.fn.filereadable(file_path) == 1 then
        completions = script_crawler.generate(binary, file_path)
    else
        log("Error: Completion file not readable: " .. file_path)
    end

    if temp_file and vim.fn.filereadable(temp_file) == 1 then
        os.remove(temp_file)
    end
elseif method == "completion_cmd" then
    local temp_file = vim.fn.tempname()
    log("Running completion command: " .. value)
    vim.fn.system(value .. " > " .. temp_file)

    local ok, result = pcall(function()
        return script_crawler.generate(binary, temp_file)
    end)

    if ok and result then
        completions = result
    else
        -- Fallback: read content and parse as help text
        local content = utils.read_file(temp_file)
        if content and content ~= "" then
            completions = parser.parse(binary, content)
        end
    end

    os.remove(temp_file)
end

if completions then
    log("Writing completions to " .. outfile)
    local lua_str = "return " .. utils.serialize(completions)
    utils.write_file(outfile, lua_str)
else
    log "Failed to generate completions"
    os.exit(1)
end

os.exit(0)
