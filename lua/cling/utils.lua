local M = {}

M.write_file = function(path, content)
    local f = io.open(path, "w")
    if f then
        f:write(content)
        f:close()
        return true
    end
    return false
end

M.read_file = function(path)
    local f = io.open(path, "r")
    if f then
        local content = f:read "*a"
        f:close()
        return content
    end
    return nil
end

--- Serializes the completion table into a Lua string.
---
--- @param tbl table The completion data to serialize.
--- @param indent? string Indentation string.
--- @return string result The serialized Lua table string.
M.serialize = function(tbl, indent)
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
            for cmd, node in pairs(t.subcommands) do
                result = result .. ind .. string.format("  [%q] = ", cmd)
                result = result .. serialize(node, ind .. "    ") .. ",\n"
            end
        end
        result = result .. ind .. "}\n"

        result = result .. ind:sub(1, -3) .. "}"
        return result
    end

    return serialize(tbl, indent)
end

return M
