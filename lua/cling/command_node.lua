local M = {}

--- @class cling.CommandNode
--- @field flags string[] List of flags available at this command level.
--- @field subcommands table<string, cling.CommandNode> Nested map of subcommands.
--- @field completion_type? "dir"|"file" Optional hint for dynamic file/directory completion.

--- Creates a well-formed CommandNode.
--- @return cling.CommandNode
function M.new()
    return { flags = {}, subcommands = {} }
end

--- Walks the command tree from `node` following `args` and returns the sorted
--- completion candidates for the word being completed (`arglead`).
---
--- Walk semantics:
--- - Descending stops at the first occurrence of `arglead` in `args`.
--- - Unknown args leave the walk at the current node.
---
--- Candidates: subcommand names and flags from the current node, plus
--- filesystem candidates when the node has a `completion_type` (collected via
--- `opts.filesystem_completer`, defaulting to `vim.fn.getcompletion`).
--- Results are filtered by `arglead` prefix and sorted.
---
--- @param node cling.CommandNode The node to start walking from.
--- @param args string[] Command-line arguments typed so far (command name excluded).
--- @param arglead string The word being completed.
--- @param opts? {filesystem_completer?: fun(arglead: string, completion_type: string): string[]} Optional overrides; inject a mock completer in tests.
--- @return string[] matches Sorted candidate strings.
--- @return cling.CommandNode current_node The node the walk ended at (so callers can detect the root).
function M.find(node, args, arglead, opts)
    opts = opts or {}
    local filesystem_completer = opts.filesystem_completer or vim.fn.getcompletion

    local current_node = node

    for _, arg in ipairs(args) do
        if arg == arglead then
            break
        end

        if current_node.subcommands[arg] then
            current_node = current_node.subcommands[arg]
        end
    end

    local candidates = {}

    for name, _ in pairs(current_node.subcommands) do
        table.insert(candidates, name)
    end

    for _, flag in ipairs(current_node.flags) do
        table.insert(candidates, flag)
    end

    if current_node.completion_type then
        local files = filesystem_completer(arglead, current_node.completion_type)
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
    return matches, current_node
end

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
            local cmd = line:match "^%s%s+(%w[%w%-]*)%s+%S" or line:match "^%s%s+(%w[%w%-]*)%s*$"
            if cmd then
                subcommands[cmd] = M.new()
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

    local node = M.new()
    node.flags = flags
    node.subcommands = subcommands
    return node
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
        subcommands[cmd] = M.new()
        subcommands[cmd].flags = clean_opts
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

    local node = M.new()
    node.flags = flags
    node.subcommands = subcommands
    node.completion_type = completion_type
    return node
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

--- Serializes a CommandNode tree into a Lua string suitable for loadstring.
--- Byte-compatible with the historical cling.utils.serialize output.
---
--- @param node cling.CommandNode
--- @param indent? string Indentation string.
--- @return string result The serialized Lua table string.
function M.serialize(node, indent)
    local serialize -- Forward declaration for recursion
    serialize = function(t, ind)
        ind = ind or "  "
        local result = "{\n"

        if t.completion_type then
            result = result .. ind .. string.format("completion_type = %q,\n", t.completion_type)
        end

        result = result .. ind .. "flags = {"
        if t.flags then
            for _, v in ipairs(t.flags) do
                result = result .. string.format("%q, ", v)
            end
        end
        result = result .. "},\n"

        result = result .. ind .. "subcommands = {\n"
        if t.subcommands then
            for cmd, child in pairs(t.subcommands) do
                result = result .. ind .. string.format("  [%q] = ", cmd)
                result = result .. serialize(child, ind .. "    ") .. ",\n"
            end
        end
        result = result .. ind .. "}\n"

        result = result .. ind:sub(1, -3) .. "}"
        return result
    end

    return serialize(node, indent)
end

--- Recursively normalizes a node and its subcommands so every node is well-formed.
---
--- @param node cling.CommandNode
local function normalize(node)
    node.flags = node.flags or {}
    node.subcommands = node.subcommands or {}
    for _, child in pairs(node.subcommands) do
        if type(child) == "table" then
            normalize(child)
        end
    end
end

--- Loads a serialized CommandNode from a cache file.
--- Returns nil if the file does not exist, contains invalid Lua, or does not
--- return a table. Missing flags/subcommands fields are normalized to {} at
--- every level of the tree.
---
--- @param path string Path to the cache file.
--- @return cling.CommandNode? node The loaded node, or nil.
function M.load(path)
    local chunk = loadfile(path)
    if not chunk then
        return nil
    end
    local ok, result = pcall(chunk)
    if not ok or type(result) ~= "table" then
        return nil
    end
    normalize(result)
    return result
end

return M
