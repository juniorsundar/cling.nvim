local cling = require "cling"

describe("cling", function()
    describe("setup", function()
        it("merges config", function()
            cling.setup {
                wrappers = {
                    { binary = "foo", command = "Foo" },
                },
            }

            assert.is_not_nil(cling.config.wrappers)
            assert.are.same(1, #cling.config.wrappers)
            assert.are.same("foo", cling.config.wrappers[1].binary)
        end)
    end)
end)
