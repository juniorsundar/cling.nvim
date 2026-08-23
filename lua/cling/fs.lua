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

return M
