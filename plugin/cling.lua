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

        local args = vim.split(cmdline, "%s+", { trimempty = true })
        if #args > 2 or (#args == 2 and arglead == "") then
            return {}
        end

        local filtered = vim.tbl_filter(function(item)
            return vim.startswith(item, arglead)
        end, completions)
        return filtered
    end,
})
