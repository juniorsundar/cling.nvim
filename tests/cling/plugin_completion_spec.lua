local assert = require "luassert"

describe("plugin/cling.lua completion", function()
    local complete_func

    before_each(function()
        vim.g.loaded_cling = nil

        local original_create_user_command = vim.api.nvim_create_user_command
        vim.api.nvim_create_user_command = function(name, _, opts)
            if name == "Cling" then
                complete_func = opts.complete
            end
        end

        dofile "plugin/cling.lua"

        vim.api.nvim_create_user_command = original_create_user_command
    end)

    it("should provide completions for the first argument", function()
        local results = complete_func("", "Cling ", 6)
        assert.are.same({ "with-env", "last", "--" }, results)

        assert.True(vim.tbl_contains(results, "last"))
        assert.True(vim.tbl_contains(results, "--"))
    end)

    it("should filter completions based on arglead", function()
        local results = complete_func("w", "Cling w", 7)
        assert.are.same({ "with-env" }, results)
    end)

    it("should return empty list if second argument is being typed", function()
        local results = complete_func("", "Cling with-env ", 15)
        assert.are.same({}, results)
    end)

    it("should return empty list if more than 2 args", function()
        local results = complete_func("foo", "Cling with-env foo", 18)
        assert.are.same({}, results)
    end)

    it("should return empty list if first argument is fully typed and space added", function()
        local results = complete_func("", "Cling last ", 11)
        assert.are.same({}, results)
    end)
end)