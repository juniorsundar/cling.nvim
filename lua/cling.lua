local core = require "cling.core"
local utils = require "cling.utils"

---
-- @class cling.Config
--- @field wrappers? cling.Wrapper[] List of wrappers to configure during setup.
local config = {
    wrappers = {},
}

local M = {}

---
-- @type cling.Config
M.config = config

local function get_plugin_root()
    local str = debug.getinfo(1, "S").source:sub(2)
    return str:match "(.*)/lua/cling%.lua$"
end

---
-- Generates or retrieves cached completion data for a wrapper.
-- Fetches from URL or executes command if necessary, then parses and caches the result.
--
-- @param wrapper cling.Wrapper The wrapper configuration.
-- @param on_complete fun(completions: cling.CommandNode) Callback when completions are available.
-- @param force? boolean If true, forces regeneration of the completion cache.
local function ensure_completion(wrapper, on_complete, force)
    local cache_dir = vim.fn.stdpath "data" .. "/cling/completions"
    if vim.fn.isdirectory(cache_dir) == 0 then
        vim.fn.mkdir(cache_dir, "p")
    end

    local cache_file = cache_dir .. "/" .. wrapper.binary .. ".lua"

    if not force and vim.fn.filereadable(cache_file) == 1 then
        local chunk = loadfile(cache_file)
        if chunk then
            on_complete(chunk())
            return
        end
    end

    local method = nil
    local value = nil

    if wrapper.help_cmd then
        method = "help_cmd"
        value = wrapper.help_cmd
    elseif wrapper.completion_file then
        method = "completion_file"
        value = wrapper.completion_file
    elseif wrapper.completion_cmd then
        method = "completion_cmd"
        value = wrapper.completion_cmd
    end

    if not method then
        return
    end

    local plugin_root = get_plugin_root()
    if not plugin_root then
        vim.notify("Could not determine plugin root for cling.nvim", vim.log.levels.ERROR)
        return
    end

    local script_path = plugin_root .. "/lua/cling/jobs/generator.lua"

    vim.notify("Generating completions for " .. wrapper.binary .. " in background...", vim.log.levels.INFO)

    vim.system({
        "nvim",
        "-l",
        script_path,
        plugin_root,
        cache_file,
        wrapper.binary,
        method,
        value,
    }, { text = true }, function(obj)
        if obj.code == 0 then
            vim.schedule(function()
                local chunk = loadfile(cache_file)
                if chunk then
                    on_complete(chunk())
                    vim.notify("Completions for " .. wrapper.binary .. " ready!", vim.log.levels.INFO)
                else
                    vim.notify("Failed to load completions for " .. wrapper.binary, vim.log.levels.ERROR)
                end
            end)
        else
            vim.schedule(function()
                vim.notify(
                    "Failed to generate completions for " .. wrapper.binary .. "\n" .. (obj.stderr or ""),
                    vim.log.levels.ERROR
                )
            end)
        end
    end)
end

---
-- Prompts for an environment file and sets it for the next command.
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

---
-- Re-runs the last executed command.
function M.run_last()
    if core.last_cmd then
        core.executor(core.last_cmd, core.last_cwd or vim.fn.getcwd())
    else
        vim.notify("No previous command executed", vim.log.levels.WARN)
    end
end

---
-- Handles the generic Cling command execution.
-- @param args table Command arguments (fargs).
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

---
-- Sets up the cling plugin with the provided options.
-- Configures wrappers.
--
-- @param args? cling.Config Configuration options.
function M.setup(args)
    M.config = vim.tbl_deep_extend("force", M.config, args or {})

    if M.config.wrappers then
        for _, wrapper in ipairs(M.config.wrappers) do
            local completions = { flags = {}, subcommands = {} }

            local function update_completions(new_completions)
                completions = new_completions
            end

            ensure_completion(wrapper, update_completions)

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
                    ensure_completion(wrapper, update_completions, true)
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
