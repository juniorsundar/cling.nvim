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

    describe("filename modifiers: path family", function()
        local saved_home
        before_each(function()
            saved_home = vim.env.HOME
            vim.env.HOME = "/home/user"
        end)
        after_each(function()
            vim.env.HOME = saved_home
        end)

        it("@%:p yields the absolute path", function()
            assert.equals(
                "cat /home/user/project/src/main.lua",
                expand.expand("cat @%:p", "/home/user/project", ctx "src/main.lua")
            )
        end)

        it("@%:~ yields the home-relative path", function()
            assert.equals(
                "cat ~/project/src/main.lua",
                expand.expand("cat @%:~", "/cwd", ctx "/home/user/project/src/main.lua")
            )
        end)

        it("@%. yields the CWD-relative path", function()
            assert.equals(
                "cat ./src/main.lua",
                expand.expand("cat @%.", "/home/user/project", ctx "/home/user/project/src/main.lua")
            )
        end)

        it("@%~ leaves a path outside HOME untouched", function()
            assert.equals("cat /opt/data/x.lua", expand.expand("cat @%:~", "/cwd", ctx "/opt/data/x.lua"))
        end)

        it("@%:h yields the directory part", function()
            assert.equals(
                "cd /home/user/project/src",
                expand.expand("cd @%:h", "/cwd", ctx "/home/user/project/src/main.lua")
            )
        end)

        it("@%:t yields the filename", function()
            assert.equals("cat main.lua", expand.expand("cat @%:t", "/cwd", ctx "/home/user/project/src/main.lua"))
        end)

        it("@%:r strips the extension", function()
            assert.equals(
                "gcc /home/user/project/src/main.o",
                expand.expand("gcc @%:r.o", "/cwd", ctx "/home/user/project/src/main.c")
            )
        end)

        it("@%:e yields the extension only", function()
            assert.equals("echo lua", expand.expand("echo @%:e", "/cwd", ctx "/home/user/project/src/main.lua"))
        end)

        it("@%:S shell-quotes a path with spaces", function()
            assert.equals(
                "cat '/home/user/My Files/a b.txt'",
                expand.expand("cat @%:S", "/cwd", ctx "/home/user/My Files/a b.txt")
            )
        end)

        it("@%:q also shell-quotes a path with spaces", function()
            assert.equals(
                "cat '/home/user/My Files/a b.txt'",
                expand.expand("cat @%:q", "/cwd", ctx "/home/user/My Files/a b.txt")
            )
        end)

        it("@%:p:h:t applies a chain left-to-right", function()
            assert.equals("echo src", expand.expand("echo @%:p:h:t", "/cwd", ctx "/home/user/project/src/main.lua"))
        end)

        it("@%:h:h:t chain drills into nested dirs", function()
            assert.equals("echo project", expand.expand("echo @%:h:h:t", "/cwd", ctx "/home/user/project/src/main.lua"))
        end)

        it("@%. resolves against the execution CWD, not the editor's", function()
            -- The file lives under the execution CWD (`/var/run/proj`), which
            -- differs from where the editor typically sits. `@%.` must be
            -- relative to where the command runs.
            local opts = ctx "/var/run/proj/src/main.lua"
            assert.equals("cd ./src/main.lua", expand.expand("cd @%.", "/var/run/proj", opts))
        end)

        it("a bare modifier does not swallow the following literal", function()
            local opts = ctx "/home/user/project/src/main.lua"
            assert.equals("x ./src/main.lua then", expand.expand("x @%. then", "/home/user/project", opts))
        end)

        it("a bare ~ does not swallow the following literal", function()
            local opts = ctx "/home/user/project/src/main.lua"
            assert.equals("x ~/project/src/main.lua then", expand.expand("x @%~ then", "/cwd", opts))
        end)

        it("@%:p:h:. resolves chain against execution CWD", function()
            local opts = ctx "/var/run/proj/src/main.lua"
            assert.equals("cd ./src", expand.expand("cd @%:p:h:.", "/var/run/proj", opts))
        end)
    end)

    describe("filename modifiers: other tokens", function()
        it("@#:t applies to the alternate file", function()
            local opts = {
                context = {
                    context_provider = {
                        current_file = function()
                            return "/f.lua"
                        end,
                        alternate_file = function()
                            return "/etc/nginx/nginx.conf"
                        end,
                    },
                },
            }
            assert.equals("tail nginx.conf", expand.expand("tail @#:t", "/cwd", opts))
        end)

        it("@#7:h applies to buffer N's file", function()
            local opts = {
                context = {
                    context_provider = {
                        current_file = function()
                            return "/f.lua"
                        end,
                        buffer_file = function()
                            return "/var/log/app/error.log"
                        end,
                    },
                },
            }
            assert.equals("cd /var/log/app", expand.expand("cd @#7:h", "/cwd", opts))
        end)

        it("@<cword>:t applies to a cursor word", function()
            local opts = {
                context = {
                    context_provider = {
                        current_file = function()
                            return "/f.lua"
                        end,
                        cursor_word = function()
                            return "src/main.lua"
                        end,
                    },
                },
            }
            assert.equals("echo main.lua", expand.expand("echo @<cword>:t", "/cwd", opts))
        end)

        it("@<cWORD>:h applies to the WORD token", function()
            local opts = {
                context = {
                    context_provider = {
                        current_file = function()
                            return "/f.lua"
                        end,
                        cursor_WORD = function()
                            return "/a/b/c"
                        end,
                    },
                },
            }
            assert.equals("ls /a/b", expand.expand("ls @<cWORD>:h", "/cwd", opts))
        end)

        it("@<cfile>:S shell-quotes a cursor file with spaces", function()
            local opts = {
                context = {
                    context_provider = {
                        current_file = function()
                            return "/f.lua"
                        end,
                        cursor_file = function()
                            return "/tmp/a b.txt"
                        end,
                    },
                },
            }
            assert.equals("cat '/tmp/a b.txt'", expand.expand("cat @<cfile>:S", "/cwd", opts))
        end)

        it("@#:. relativizes alternate against execution CWD", function()
            local opts = {
                context = {
                    context_provider = {
                        current_file = function()
                            return "/f.lua"
                        end,
                        alternate_file = function()
                            return "/var/run/proj/src/main.lua"
                        end,
                    },
                },
            }
            assert.equals("cd ./src/main.lua", expand.expand("cd @#.", "/var/run/proj", opts))
        end)
    end)

    describe("unsupported substitution modifiers", function()
        local function opts_with(extra)
            extra = extra or {}
            return {
                context = {
                    context_provider = vim.tbl_extend("force", {
                        current_file = function()
                            return "/home/user/project/src/main.lua"
                        end,
                    }, extra),
                },
            }
        end

        it("@%:s/a/b/ passes through verbatim, not partially expanded", function()
            assert.equals("cat @%:s/a/b/", expand.expand("cat @%:s/a/b/", "/cwd", opts_with()))
        end)

        it("@%:gs/a/b/ passes through verbatim", function()
            assert.equals("cat @%:gs/a/b/", expand.expand("cat @%:gs/a/b/", "/cwd", opts_with()))
        end)

        it("substitution on another token also falls back", function()
            local opts = {
                context = {
                    context_provider = {
                        current_file = function()
                            return "/f.lua"
                        end,
                        cursor_word = function()
                            return "foo"
                        end,
                    },
                },
            }
            assert.equals("echo @<cword>:s/o/0/", expand.expand("echo @<cword>:s/o/0/", "/cwd", opts))
        end)

        it("substitution on bare @# falls back", function()
            local opts = opts_with {
                alternate_file = function()
                    return "/etc/nginx/nginx.conf"
                end,
            }
            assert.equals("cat @#:s/ngx/http/", expand.expand("cat @#:s/ngx/http/", "/cwd", opts))
        end)

        it("substitution on @#N falls back", function()
            local opts = opts_with {
                buffer_file = function()
                    return "/var/log/app/error.log"
                end,
            }
            assert.equals("tail @#3:s/error/warn/", expand.expand("tail @#3:s/error/warn/", "/cwd", opts))
        end)
    end)

    describe("passthrough", function()
        local cases = {
            { "plain command stays verbatim", "echo hello world", "echo hello world" },
            { "bare @ alone passes through", "@", "@" },
            { "bare @ before a space passes through", "echo @ now", "echo @ now" },
            { "@@ yields a single literal @", "echo @@", "echo @" },
            { "bare @ not followed by a token passes through", "mail me@example.com", "mail me@example.com" },
            { "@ at end of input passes through", "grep foo @", "grep foo @" },
            { "marker followed by an unrecognized char passes through", "echo @q", "echo @q" },
            { "multiple unrecognized @ markers pass through", "a@b c@d e@f", "a@b c@d e@f" },
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

    describe("byte-identical guarantee", function()
        -- A command line with no recognized marked token must be returned
        -- byte-identical to its input, regardless of incidental `@`, `%`,
        -- `#`, `<`, `>`, or backticks. This is the zero-shell-casualty lock.
        local no_marker_cases = {
            "ls -la",
            "cat README.md",
            "make build # note",
            "sort < in > out",
            "echo `date`",
            "printf '%s\\n' hi",
            "mail me@example.com",
            "echo @q",
            "a@b c@d",
            "git log --oneline -10 | head",
        }

        for _, cmd in ipairs(no_marker_cases) do
            it(string.format("%q is returned byte-identical", cmd), function()
                assert.equals(cmd, expand.expand(cmd, "/cwd", ctx "/f.lua"))
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
