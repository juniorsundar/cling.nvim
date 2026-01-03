--- @module 'cling.crawlers.completion_script_crawler'

local M = {}

-- Helper to find the bash wrapper
local function get_bash_wrapper()
    local runtime_files = vim.api.nvim_get_runtime_file("scripts/get_completion.bash", false)
    if #runtime_files > 0 then
        return runtime_files[1]
    end

    local cwd_wrapper = vim.fn.getcwd() .. "/scripts/get_completion.bash"
    if vim.fn.filereadable(cwd_wrapper) == 1 then
        return cwd_wrapper
    end

    return "scripts/get_completion.bash"
end

-- Utility to split string by newline
local function split_lines(str)
    local lines = {}
    for line in str:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    return lines
end

-- Find entrypoint function name in bash script
local function find_entrypoint(script_path, binary_name)
    local f = io.open(script_path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()

    for line in content:gmatch("[^\r\n]+") do
        if line:match("^%s*complete") and line:match("%-F") and line:match(binary_name) then
            local func_name = line:match("%-F%s+([%w_:]+)")
            if func_name then return func_name end
        end
    end

    local func_name = content:match("complete%s+.-%-F%s+([%w_:]+)")
    return func_name
end

-- Call the bash wrapper to get completions
local function get_completions(bash_script, func_name, command_line)
    local wrapper = get_bash_wrapper()

    local cmd = string.format("%s %s %s %s",
        vim.fn.shellescape(wrapper),
        vim.fn.shellescape(bash_script),
        vim.fn.shellescape(func_name),
        vim.fn.shellescape(command_line)
    )
    local output = vim.fn.system(cmd)

    local raw_lines = split_lines(output)
    local seen = {}
    local distinct = {}

    for _, line in ipairs(raw_lines) do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" and not seen[trimmed] then
            seen[trimmed] = true
            table.insert(distinct, trimmed)
        end
    end

    table.sort(distinct)
    return distinct
end

local function build_tree(bash_script, func_name, binary_name, max_depth)
    local tree = {
        flags = {},
        subcommands = {}
    }

    local queue = {}
    table.insert(queue, {binary_name, 0, tree})

    local head = 1

    while head <= #queue do
        local item = queue[head]
        head = head + 1

        local current_cmd = item[1]
        local depth = item[2]
        local current_node = item[3]

        if depth < max_depth then
            local query_cmd = current_cmd .. " "
            local candidates = get_completions(bash_script, func_name, query_cmd)

            -- Also try to fetch flags explicitly
            local flag_query_cmd = current_cmd .. " -"
            local flag_candidates = get_completions(bash_script, func_name, flag_query_cmd)

            for _, cand in ipairs(flag_candidates) do
                table.insert(candidates, cand)
            end

            local flags = {}
            local subcommands = {}
            local seen_candidates = {}

            for _, cand in ipairs(candidates) do
                if not seen_candidates[cand] then
                    seen_candidates[cand] = true
                    if cand:sub(1, 1) == "-" then
                        table.insert(flags, cand)
                    else
                        table.insert(subcommands, cand)
                    end
                end
            end

            current_node.flags = flags
            current_node.subcommands = {}

            if depth + 1 < max_depth then
                for _, sub in ipairs(subcommands) do
                    current_node.subcommands[sub] = {}
                    local new_cmd = current_cmd .. " " .. sub
                    table.insert(queue, {new_cmd, depth + 1, current_node.subcommands[sub]})
                end
            end
        end
    end

    return tree
end

function M.generate(binary, completion_file)
    if not completion_file or vim.fn.filereadable(completion_file) == 0 then
        vim.notify("Completion file not found: " .. (completion_file or "nil"), vim.log.levels.ERROR)
        return nil
    end

    local func_name = find_entrypoint(completion_file, binary)
    if not func_name then
        -- vim.notify("Could not find completion function in " .. completion_file, vim.log.levels.ERROR)
        return nil
    end

    vim.notify("Generating completions from script for " .. binary .. "...", vim.log.levels.INFO)
    return build_tree(completion_file, func_name, binary, 4) -- Default depth 4
end

return M
