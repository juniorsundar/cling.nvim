local M = {}

--- @class cling.CommandNode
--- @field flags string[] List of flags available at this command level.
--- @field subcommands table<string, cling.CommandNode> Nested map of subcommands.
--- @field completion_type? "dir"|"file" Optional hint for dynamic file/directory completion.

--- Parses "Usage:" style help text (e.g., docker --help)
--- @param content string
--- @return cling.CommandNode
function M.parse_help(content)
    local flags = {}
    local subcommands = {}
    local seen_flags = {}

    local is_commands_section = false
    local is_options_section = false

    for line in content:gmatch "[^\r\n]+" do
        if line:match "^%s*[%w%s]*Commands:%s*$" or line:match "^%s*[A-Z%s]+COMMANDS%s*$" then
            is_commands_section = true
            is_options_section = false
        elseif
            line:match "^%s*[%w%s]*Options:%s*$"
            or line:match "^%s*[%w%s]*Flags:%s*$"
            or line:match "^%s*[A-Z%s]+OPTIONS%s*$"
            or line:match "^%s*[A-Z%s]+FLAGS%s*$"
        then
            is_commands_section = false
            is_options_section = true
        elseif line:match "^%S" and not line:match "^%s*[A-Z%s]+$" then
            is_commands_section = false
            is_options_section = false
        end

        if is_commands_section then
            local cmd = line:match "^%s%s+(%w[%w%-]*)%s"
            if cmd then
                subcommands[cmd] = { flags = {}, subcommands = {} }
            end
        end

        if is_options_section then
            for flag in line:gmatch "%-%-[%w%-]+" do
                if not seen_flags[flag] then
                    table.insert(flags, flag)
                    seen_flags[flag] = true
                end
            end
            for flag in line:gmatch "%s(%-[%w])%f[%s,]" do
                if not seen_flags[flag] then
                    table.insert(flags, flag)
                    seen_flags[flag] = true
                end
            end
        end
    end

    table.sort(flags)

    return {
        flags = flags,
        subcommands = subcommands,
    }
end

--- Parses bash completion scripts
--- @param binary_name string
--- @param content string
--- @return cling.CommandNode
function M.parse_bash(binary_name, content)
    local cmd_map = {}
    local opts_map = {}

    local mapping_pattern = binary_name .. [[,([%w%-]+)%)%s+cmd="]] .. "(" .. binary_name .. [[__[%w%-]+)"]]
    for cmd, func in content:gmatch(mapping_pattern) do
        cmd_map[cmd] = func
    end

    for func, opts_str in content:gmatch [[([%w_]+)%)%s+opts="([^"]+)"]] do
        local opts = {}
        for opt in opts_str:gmatch "%S+" do
            table.insert(opts, opt)
        end
        opts_map[func] = opts
    end

    local root_opts = opts_map[binary_name] or {}
    local flags = {}
    local root_cmds = {}

    for _, o in ipairs(root_opts) do
        if vim.startswith(o, "-") then
            table.insert(flags, o)
        else
            table.insert(root_cmds, o)
        end
    end

    local subcommands = {}
    for _, cmd in ipairs(root_cmds) do
        local func_name = cmd_map[cmd]
        if not func_name then
            func_name = binary_name .. "__" .. cmd
        end
        local cmd_opts = opts_map[func_name] or {}
        local clean_opts = {}
        for _, o in ipairs(cmd_opts) do
            if vim.startswith(o, "-") then
                table.insert(clean_opts, o)
            end
        end
        subcommands[cmd] = { flags = clean_opts, subcommands = {} }
    end

    if #flags == 0 and vim.tbl_count(subcommands) == 0 then
        local seen = {}
        for line in content:gmatch "[^\r\n]+" do
            local trimmed = line:match "^%s*(.-)%s*$"
            if trimmed and trimmed:match "^[%-%w|]+%)$" then
                local pattern = trimmed:sub(1, -2)
                for part in pattern:gmatch "[^|]+" do
                    if part:match "^%-" and not seen[part] then
                        table.insert(flags, part)
                        seen[part] = true
                    end
                end
            end
            for flag in line:gmatch "%-%-[%w%-]+" do
                if not seen[flag] then
                    table.insert(flags, flag)
                    seen[flag] = true
                end
            end
        end
        table.sort(flags)
    end

    local completion_type = nil
    if content:match "compgen%s+%-A%s+directory" or content:match "compgen%s+%-d" then
        completion_type = "dir"
    elseif
        content:match "compgen%s+%-A%s+file"
        or content:match "compgen%s+%-f"
        or content:match "_filedir"
        or content:match "%-o%s+filenames"
    then
        completion_type = "file"
    end

    return {
        flags = flags,
        subcommands = subcommands,
        completion_type = completion_type,
    }
end

--- Parses completion content and returns a completion tree.
--- Switches between bash script parsing and help text parsing based on content.
---
--- @param binary_name string The name of the binary (e.g., "jj").
--- @param content string The content to parse.
--- @return cling.CommandNode completions The parsed completion configuration.
function M.parse(binary_name, content)
    if content:match 'cmd="' or content:match 'opts="' or content:match "function%s+%w+" then
        return M.parse_bash(binary_name, content)
    end

    if content:match "Usage:" then
        local help_result = M.parse_help(content)
        if #help_result.flags > 0 or vim.tbl_count(help_result.subcommands) > 0 then
            return help_result
        end
    end

    return M.parse_bash(binary_name, content)
end

return M
