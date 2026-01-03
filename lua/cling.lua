local core = require "cling.core"
local utils = require "cling.utils"
local parser = require "cling.parser"
local crawler = require "cling.crawlers.help_crawler"
local script_crawler = require "cling.crawlers.completion_script_crawler"

--- @class cling.Config
--- @field wrappers? cling.Wrapper[] List of wrappers to configure during setup.
local config = {
    wrappers = {},
}

local M = {}

--- @type cling.Config
M.config = config

--- Serializes the completion table into a Lua string.
---
--- @param tbl cling.CommandNode The completion data to serialize.
--- @param indent? string Indentation string.
--- @return string result The serialized Lua table string.
local function serialize(tbl, indent)
    indent = indent or "  "
    local result = "{\n"

    if tbl.completion_type then
        result = result .. indent .. string.format("completion_type = %q,\n", tbl.completion_type)
    end

    -- Serialize flags
    result = result .. indent .. "flags = {"
    if tbl.flags then
        for _, v in ipairs(tbl.flags) do
            result = result .. string.format("%q, ", v)
        end
    end
    result = result .. "},\n"

    -- Serialize subcommands recursively
    result = result .. indent .. "subcommands = {\n"
    if tbl.subcommands then
        for cmd, node in pairs(tbl.subcommands) do
            result = result .. indent .. string.format("  [%q] = ", cmd)
            result = result .. serialize(node, indent .. "    ") .. ",\n"
        end
    end
    result = result .. indent .. "}\n"

    result = result .. indent:sub(1, -3) .. "}"
    return result
end

--- Generates or retrieves cached completion data for a wrapper.
--- Fetches from URL or executes command if necessary, then parses and caches the result.
---
--- @param wrapper cling.Wrapper The wrapper configuration.
--- @param force? boolean If true, forces regeneration of the completion cache.
--- @return cling.CommandNode completions The generated or cached completion data.
local function generate_completion(wrapper, force)
    local cache_dir = vim.fn.stdpath "data" .. "/cling/completions"
    if vim.fn.isdirectory(cache_dir) == 0 then
        vim.fn.mkdir(cache_dir, "p")
    end

    local cache_file = cache_dir .. "/" .. wrapper.binary .. ".lua"

    if not force and vim.fn.filereadable(cache_file) == 1 then
        local chunk = loadfile(cache_file)
        if chunk then
            return chunk()
        end
    end

    local completions = nil

    if wrapper.help_cmd then
        completions = crawler.generate(wrapper.binary, wrapper.help_cmd)
    elseif wrapper.completion_file then
        local file_path = wrapper.completion_file
        local temp_file = nil

        if wrapper.completion_file:match "^https?://" then
            temp_file = vim.fn.tempname()
            vim.notify(
                string.format("Fetching completions for %s from %s", wrapper.binary, wrapper.completion_file),
                vim.log.levels.INFO
            )
            vim.fn.system({ "curl", "-s", "-o", temp_file, wrapper.completion_file })
            file_path = temp_file
        else
            file_path = vim.fn.expand(wrapper.completion_file)
        end

        if vim.fn.filereadable(file_path) == 1 then
            completions = script_crawler.generate(wrapper.binary, file_path)
        else
            vim.notify("Completion file not readable: " .. file_path, vim.log.levels.ERROR)
        end

        if temp_file and vim.fn.filereadable(temp_file) == 1 then
            os.remove(temp_file)
        end
    elseif wrapper.completion_cmd then
        local handle = io.popen(wrapper.completion_cmd)
        if handle then
            local content = handle:read "*a"
            handle:close()
            completions = parser.parse(wrapper.binary, content)
        end
    end

    if completions then
        local lua_str = "return " .. serialize(completions)
        utils.write_file(cache_file, lua_str)
        return completions
    else
        vim.notify("Failed to obtain completion content for " .. wrapper.binary, vim.log.levels.ERROR)
    end

    return { flags = {}, subcommands = {} }
end

--- Prompts for an environment file and sets it for the next command.
function M.with_env()
    local env_file =
        vim.fn.input("Path to .env file: ", core.last_env or vim.fs.joinpath(vim.fn.getcwd(), ".env"), "file")
    if env_file == nil or env_file == "" then
        vim.notify("Cancelled", vim.log.levels.WARN)
        return
    end
    core.last_env = env_file
    M.on_cli_command { fargs = {} }
end

--- Re-runs the last executed command.
function M.run_last()
    if core.last_cmd then
        core.executor(core.last_cmd, core.last_cwd or vim.fn.getcwd())
    else
        vim.notify("No previous command executed", vim.log.levels.WARN)
    end
end

--- Handles the generic Cling command execution.
--- @param args table Command arguments (fargs).
function M.on_cli_command(args)
    local fargs = args.fargs
    if #fargs == 0 then
        local cmd = vim.fn.input("Cling command: ", core.last_cmd or "")
        if cmd == nil or cmd == "" then
            vim.notify("Cancelled", vim.log.levels.WARN)
            return
        end

        local default_cwd = core.last_cwd or vim.fn.getcwd()
        local cwd = vim.fn.input("CWD: ", default_cwd, "dir")
        if cwd == nil or cwd == "" then
            vim.notify("Cancelled", vim.log.levels.WARN)
            return
        end

        core.executor(cmd, cwd)
        return
    end

    if fargs[1] == "--" then
        local cmd_parts = {}
        for i = 2, #fargs do
            table.insert(cmd_parts, fargs[i])
        end
        core.executor(table.concat(cmd_parts, " "), vim.fn.getcwd())
        return
    elseif fargs[1] == "with-env" then
        M.with_env()
        return
    elseif fargs[1] == "last" then
        M.run_last()
        return
    else
        vim.notify(
            "Error: Unknown argument '" .. fargs[1] .. "'. Did you mean --, with-env, or last?",
            vim.log.levels.ERROR
        )
        return
    end
end

--- Sets up the cling plugin with the provided options.
--- Configures wrappers.
---
--- @param args? cling.Config Configuration options.
function M.setup(args)
    M.config = vim.tbl_deep_extend("force", M.config, args or {})

    if M.config.wrappers then
        for _, wrapper in ipairs(M.config.wrappers) do
            local completions = generate_completion(wrapper)

            local complete_func = function(arglead, cmdline, _)
                local args = vim.split(cmdline, "%s+")
                table.remove(args, 1) -- remove command name

                local current_node = completions

                for _, arg in ipairs(args) do
                    if arg == arglead then
                        break
                    end

                    if current_node.subcommands and current_node.subcommands[arg] then
                        current_node = current_node.subcommands[arg]
                    end
                end

                local candidates = {}

                if current_node.subcommands then
                    for name, _ in pairs(current_node.subcommands) do
                        table.insert(candidates, name)
                    end
                end

                if current_node.flags then
                    for _, flag in ipairs(current_node.flags) do
                        table.insert(candidates, flag)
                    end
                end

                if current_node == completions then
                    table.insert(candidates, "--reparse-completions")
                end

                if current_node.completion_type then
                    local files = vim.fn.getcompletion(arglead, current_node.completion_type)
                    for _, f in ipairs(files) do
                        table.insert(candidates, f)
                    end
                end

                local matches = {}
                for _, cand in ipairs(candidates) do
                    if vim.startswith(cand, arglead) then
                        table.insert(matches, cand)
                    end
                end
                table.sort(matches)
                return matches
            end

            vim.api.nvim_create_user_command(wrapper.command, function(cargs)
                if cargs.fargs[1] == "--reparse-completions" then
                    completions = generate_completion(wrapper, true)
                    vim.notify("Reparsed completions for " .. wrapper.binary, vim.log.levels.INFO)
                    return
                end

                local cmd_parts = { wrapper.binary }
                for _, arg in ipairs(cargs.fargs) do
                    table.insert(cmd_parts, arg)
                end
                local cmd = table.concat(cmd_parts, " ")

                core.executor(cmd, vim.fn.getcwd(), {
                    title = "[" .. wrapper.command .. "]",
                    on_open = function(buf)
                        if wrapper.keymaps then
                            wrapper.keymaps(buf)
                        end
                    end,
                })
            end, {
                nargs = "*",
                desc = "Wrapper for " .. wrapper.binary,
                complete = complete_func,
            })
        end
    end
end

return M
