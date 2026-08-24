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

    describe("@# (alternate file)", function()
        local function ctx_with(extra)
            return {
                context = {
                    context_provider = vim.tbl_extend("force", {
                        current_file = function()
                            return "/f.lua"
                        end,
                    }, extra),
                },
            }
        end

        it("expands to the alternate file's path", function()
            local opts = ctx_with {
                alternate_file = function()
                    return "other.rs"
                end,
            }
            assert.equals("cat /cwd/other.rs", expand.expand("cat @#", "/cwd", opts))
        end)
    end)

    describe("@#N (buffer N's file)", function()
        local seen = nil
        local function opts_buf()
            return {
                context = {
                    context_provider = {
                        current_file = function()
                            return "/f.lua"
                        end,
                        buffer_file = function(n)
                            seen = n
                            return "buf" .. n .. ".txt"
                        end,
                    },
                },
            }
        end

        it("expands to buffer N's file path", function()
            assert.equals("cat /cwd/buf3.txt", expand.expand("cat @#3", "/cwd", opts_buf()))
            assert.equals(3, seen)
        end)

        it("parses multi-digit buffer numbers", function()
            assert.equals("cat /cwd/buf42.txt", expand.expand("cat @#42", "/cwd", opts_buf()))
            assert.equals(42, seen)
        end)
    end)

    describe("cursor tokens", function()
        local function cursor_ctx(extra)
            return {
                context = {
                    context_provider = vim.tbl_extend("force", {
                        current_file = function()
                            return "/f.lua"
                        end,
                    }, extra),
                },
            }
        end

        it("@<cword> expands to the word under the cursor", function()
            local opts = cursor_ctx {
                cursor_word = function()
                    return "my_func"
                end,
            }
            assert.equals("grep my_func src/", expand.expand("grep @<cword> src/", "/cwd", opts))
        end)

        it("@<cWORD> expands to the whitespace-delimited WORD, punctuation preserved", function()
            local opts = cursor_ctx {
                cursor_WORD = function()
                    return "foo.bar"
                end,
            }
            assert.equals("test foo.bar", expand.expand("test @<cWORD>", "/cwd", opts))
        end)

        it("@<cfile> expands to the file path under the cursor", function()
            local opts = cursor_ctx {
                cursor_file = function()
                    return "src/main.lua"
                end,
            }
            assert.equals("cat /cwd/src/main.lua", expand.expand("cat @<cfile>", "/cwd", opts))
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
            { "unmarked #N passes through", "bufdo b3 | echo ok #3", "bufdo b3 | echo ok #3" },
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

    describe("new-token passthrough", function()
        local function ctx_with(extra)
            return {
                context = {
                    context_provider = vim.tbl_extend("force", {
                        current_file = function()
                            return "/f.lua"
                        end,
                    }, extra),
                },
            }
        end

        it("unrecognized @<...> sequence passes through", function()
            assert.equals("echo @<cfoo>", expand.expand("echo @<cfoo>", "/cwd", ctx ""))
        end)

        it("@<cword> passes through when the provider is absent", function()
            assert.equals(
                "grep @<cword> .",
                expand.expand("grep @<cword> .", "/cwd", { context = { context_provider = {} } })
            )
        end)

        it("@#N passes through when buffer N has no file", function()
            local opts = ctx_with {
                buffer_file = function()
                    return ""
                end,
            }
            assert.equals("cat @#7", expand.expand("cat @#7", "/cwd", opts))
        end)

        it("@#12 followed by more text consumes only the digits", function()
            local seen = nil
            local opts = ctx_with {
                buffer_file = function(n)
                    seen = n
                    return "b.txt"
                end,
            }
            assert.equals("cat /cwd/b.txt and 12 more", expand.expand("cat @#12 and 12 more", "/cwd", opts))
            assert.equals(12, seen)
        end)
    end)
end)
