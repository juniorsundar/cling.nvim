if vim.g.loaded_cling then
    return
end
vim.g.loaded_cling = 1

vim.api.nvim_create_user_command("Cling", function(opts)
    require("cling").on_cli_command(opts)
end, { nargs = "*", desc = "Generic cling command" })
