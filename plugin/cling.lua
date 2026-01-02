if vim.g.loaded_cling then
    return
end
vim.g.loaded_cling = 1

vim.api.nvim_create_user_command("Cling", function(opts)
    require("cling").on_cli_command(opts)
end, {
    nargs = "*",
    desc = "Generic cling command",
    complete = function(arglead, cmdline, _)
        local completions = { "with-env", "last", "--" }

        if cmdline:find "%-%-" then
            return {}
        end

        local filtered = {}
        for _, item in ipairs(completions) do
            if vim.startswith(item, arglead) then
                table.insert(filtered, item)
            end
        end
        return filtered
    end,
})
