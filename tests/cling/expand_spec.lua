local expand = require "cling.expand"

describe("expand", function()
    -- Fake current-file provider injected through opts; no real buffer state.
    local function ctx(current_file)
        return {
            context = {
                context_provider = {
                    current_file = function()
                        return current_file
                    end,
                },
            },
        }
    end

    describe("@% (current file)", function()
        it("expands to the absolute path of the current file", function()
            assert.equals(
                "cat /home/user/project/src/main.lua",
                expand.expand("cat @%", "/home/user/project", ctx "/home/user/project/src/main.lua")
            )
        end)

        it("resolves to an absolute path even when the provider returns an editor-relative one", function()
            assert.equals(
                "cat /home/user/project/README.md",
                expand.expand("cat @%", "/home/user/project", ctx "README.md")
            )
        end)
    end)

    describe("passthrough", function()
        local cases = {
            { "plain command stays verbatim", "echo hello world", "echo hello world" },
            { "@@ yields a single literal @", "echo @@", "echo @" },
            { "bare @ not followed by a token passes through", "mail me@example.com", "mail me@example.com" },
            { "@ at end of input passes through", "grep foo @", "grep foo @" },
            { "unmarked % passes through", "printf '%s\\n' hi", "printf '%s\\n' hi" },
            { "unmarked # passes through", "make build # note", "make build # note" },
            { "unmarked < and > pass through", "sort < in > out", "sort < in > out" },
            { "backticks pass through", "echo `date`", "echo `date`" },
            { "marked and literal text mix", "cat @% && printf '%s\\n' done", "cat /f.lua && printf '%s\\n' done" },
            { "empty line stays empty", "", "" },
        }

        for _, case in ipairs(cases) do
            it(case[1], function()
                assert.equals(case[3], expand.expand(case[2], "/cwd", ctx "/f.lua"))
            end)
        end
    end)
end)
