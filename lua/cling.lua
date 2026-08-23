local command_node = require "cling.command_node"
local core = require "cling.core"
local history = require "cling.history"

--- @class cling.Config
--- @field wrappers? cling.Wrapper[] List of wrappers to configure during setup.
--- @field separate_history? boolean If false, disable per-CWD history separation and use Neovim's native input history. Defaults to true.
local config = {
    wrappers = {},
    separate_history = true,
}

local M = {}

--- @type cling.Config
M.config = config

local function get_plugin_root()
    local str = debug.getinfo(1, "S").source:sub(2)
    return str:match "(.*)/lua/cling%.lua$"
end

--- Generates or retrieves cached completion data for a wrapper.
--- Fetches from URL or executes command if necessary, then parses and caches the result.
---
--- @param wrapper cling.Wrapper The wrapper configuration.
--- @param on_complete fun(completions: cling.CommandNode) Callback when completions are available.
--- @param force? boolean If true, forces regeneration of the completion cache.
local function ensure_completion(wrapper, on_complete, force)
    local cache_dir = vim.fn.stdpath "data" .. "/cling/completions"
    if vim.fn.isdirectory(cache_dir) == 0 then
        vim.fn.mkdir(cache_dir, "p")
    end

    local binary_name = type(wrapper.binary) == "function" and wrapper.command or wrapper.binary
    local cache_file = cache_dir .. "/" .. binary_name .. ".lua"

    if not force and vim.fn.filereadable(cache_file) == 1 then
        local node = command_node.load(cache_file)
        if node then
            on_complete(node)
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

    vim.notify("Generating completions for " .. binary_name .. " in background...", vim.log.levels.INFO)

    vim.system({
        "nvim",
        "-l",
        script_path,
        plugin_root,
        cache_file,
        binary_name,
        method,
        value,
    }, { text = true }, function(obj)
        if obj.code == 0 then
            vim.schedule(function()
                local node = command_node.load(cache_file)
                if node then
                    on_complete(node)
                    vim.notify("Completions for " .. binary_name .. " ready!", vim.log.levels.INFO)
                else
                    vim.notify("Failed to load completions for " .. binary_name, vim.log.levels.ERROR)
                end
            end)
        else
            vim.schedule(function()
                vim.notify(
                    "Failed to generate completions for " .. binary_name .. "\n" .. (obj.stderr or ""),
                    vim.log.levels.ERROR
                )
            end)
        end
    end)
end

--- Prompts for an environment file and sets it for the next command.
--- @param smods? table Command modifiers forwarded from on_cli_command.
function M.with_env(smods)
    local ok, env_file =
        pcall(vim.fn.input, "Path to .env file: ", core.last_env or vim.fs.joinpath(vim.fn.getcwd(), ".env"), "file")
    if not ok or not env_file then
        return
    end
    core.last_env = env_file
    M.on_cli_command { fargs = {}, smods = smods }
end

--- Re-runs the last executed command.
function M.run_last()
    if core.last_cmd then
        core.executor(core.last_cmd, core.last_cwd or vim.fn.getcwd(), { smods = core.last_smods })
    else
        vim.notify("No previous command executed", vim.log.levels.WARN)
    end
end

--- Handles the generic Cling command execution.
--- @param args table Command arguments (fargs).
function M.on_cli_command(args)
    local fargs = args.fargs
    if #fargs == 0 then
        local prompt_cwd = core.last_cwd or vim.fn.getcwd()

        if M.config.separate_history ~= false then
            history.load(prompt_cwd)
            vim.fn.inputsave()
            vim.fn.histdel "input"
            for _, entry in ipairs(history.get(prompt_cwd)) do
                vim.fn.histadd("input", entry)
            end
        end

        vim.keymap.set("c", "<C-l>", "<C-u>", { noremap = true })
        vim.keymap.set("c", "<M-BS>", "<C-w>", { noremap = true })
        local ok, cmd = pcall(vim.fn.input, "Cling command: ", core.last_cmd or "")
        vim.keymap.del("c", "<C-l>")
        vim.keymap.del("c", "<M-BS>")
        vim.fn.inputrestore()

        if not ok or not cmd or cmd == "" then
            return
        end

        local ok2, cwd = pcall(vim.fn.input, "CWD: ", prompt_cwd, "dir")
        if not ok2 or not cwd or cwd == "" then
            return
        end

        core.executor(cmd, cwd, { smods = args.smods, no_cwd_history = M.config.separate_history == false })
        return
    end

    if fargs[1] == "--" then
        local cmd_parts = {}
        for i = 2, #fargs do
            table.insert(cmd_parts, fargs[i])
        end
        core.executor(table.concat(cmd_parts, " "), vim.fn.getcwd(), { smods = args.smods })
        return
    elseif fargs[1] == "with-env" then
        M.with_env(args.smods)
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
            local completions = { flags = {}, subcommands = {} }
            local wrapper_binary_name = type(wrapper.binary) == "function" and wrapper.command or wrapper.binary

            local function update_completions(new_completions)
                completions = new_completions
            end

            ensure_completion(wrapper, update_completions)

            local complete_func = function(arglead, cmdline, _)
                local args = vim.split(cmdline, "%s+")
                table.remove(args, 1)

                local matches, current_node = command_node.find(completions, args, arglead)

                if current_node == completions and vim.startswith("--reparse-completions", arglead) then
                    table.insert(matches, "--reparse-completions")
                end

                return matches
            end

            vim.api.nvim_create_user_command(wrapper.command, function(cargs)
                if cargs.fargs[1] == "--reparse-completions" then
                    ensure_completion(wrapper, update_completions, true)
                    return
                end

                local binary = type(wrapper.binary) == "function" and wrapper.binary() or wrapper.binary
                local cmd_parts = { binary }
                for _, arg in ipairs(cargs.fargs) do
                    table.insert(cmd_parts, arg)
                end
                local cmd = table.concat(cmd_parts, " ")

                local resolved_cwd
                if type(wrapper.cwd) == "function" then
                    resolved_cwd = wrapper.cwd()
                elseif type(wrapper.cwd) == "string" then
                    resolved_cwd = wrapper.cwd
                else
                    resolved_cwd = vim.fn.getcwd()
                end

                core.executor(cmd, resolved_cwd, {
                    title = "[" .. wrapper.command .. "]",
                    smods = cargs.smods,
                    close_on_exit = wrapper.close_on_exit,
                    no_history = wrapper.no_history ~= false,
                    on_open = function(buf)
                        if wrapper.keymaps then
                            wrapper.keymaps(buf)
                        end
                    end,
                    on_close = wrapper.on_close,
                })
            end, {
                nargs = "*",
                desc = "Wrapper for " .. wrapper_binary_name,
                complete = complete_func,
            })
        end
    end
end

return M
