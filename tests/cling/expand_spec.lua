local expand = require "cling.expand"
local stub = require "luassert.stub"

describe("expand", function()
    local expand_stub

    local function revert_stub()
        if expand_stub then
            expand_stub:revert()
            expand_stub = nil
        end
    end

    -- Stubs native expand(); every spec maps to its resolved value, unset
    -- specs resolve to "" (the unset case).
    local function ctx(resolutions)
        revert_stub()
        expand_stub = stub(vim.fn, "expand", function(spec)
            return resolutions[spec] or ""
        end)
    end

    after_each(revert_stub)

    describe("@% (current file)", function()
        it("expands to the absolute path of the current file", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("cat /home/user/project/src/main.lua", expand.expand("cat @%", "/home/user/project"))
        end)

        it("absolutizes an editor-relative path against the execution CWD", function()
            ctx { ["%"] = "README.md" }
            assert.equals("cat /home/user/project/README.md", expand.expand("cat @%", "/home/user/project"))
        end)
    end)

    describe("@# (alternate file)", function()
        it("expands to the alternate file's path", function()
            ctx { ["%"] = "/f.lua", ["#"] = "other.rs" }
            assert.equals("cat /cwd/other.rs", expand.expand("cat @#", "/cwd"))
        end)
    end)

    describe("@#N (buffer N's file)", function()
        it("expands to buffer N's file path", function()
            ctx { ["%"] = "/f.lua", ["#3"] = "buf3.txt" }
            assert.equals("cat /cwd/buf3.txt", expand.expand("cat @#3", "/cwd"))
            assert.equals("#3", expand_stub.calls[1].refs[1])
        end)

        it("parses multi-digit buffer numbers", function()
            ctx { ["%"] = "/f.lua", ["#42"] = "buf42.txt" }
            assert.equals("cat /cwd/buf42.txt", expand.expand("cat @#42", "/cwd"))
        end)

        it("@#12 followed by more text consumes only the digits", function()
            ctx { ["%"] = "/f.lua", ["#12"] = "b.txt" }
            assert.equals("cat /cwd/b.txt and 12 more", expand.expand("cat @#12 and 12 more", "/cwd"))
            assert.equals("#12", expand_stub.calls[1].refs[1])
        end)
    end)

    describe("cursor tokens", function()
        it("@<cword> expands to the word under the cursor", function()
            ctx { ["%"] = "/f.lua", ["<cword>"] = "my_func" }
            assert.equals("grep my_func src/", expand.expand("grep @<cword> src/", "/cwd"))
        end)

        it("@<cWORD> expands to the whitespace-delimited WORD, punctuation preserved", function()
            ctx { ["%"] = "/f.lua", ["<cWORD>"] = "foo.bar" }
            assert.equals("test foo.bar", expand.expand("test @<cWORD>", "/cwd"))
        end)

        it("@<cfile> expands to the file path under the cursor", function()
            ctx { ["%"] = "/f.lua", ["<cfile>"] = "src/main.lua" }
            assert.equals("cat /cwd/src/main.lua", expand.expand("cat @<cfile>", "/cwd"))
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
            ctx { ["%"] = "src/main.lua" }
            assert.equals("cat /home/user/project/src/main.lua", expand.expand("cat @%:p", "/home/user/project"))
        end)

        it("@%:~ yields the home-relative path", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("cat ~/project/src/main.lua", expand.expand("cat @%:~", "/cwd"))
        end)

        it("@%. yields the CWD-relative path", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("cat ./src/main.lua", expand.expand("cat @%.", "/home/user/project"))
        end)

        it("@%~ leaves a path outside HOME untouched", function()
            ctx { ["%"] = "/opt/data/x.lua" }
            assert.equals("cat /opt/data/x.lua", expand.expand("cat @%:~", "/cwd"))
        end)

        it("@%:h yields the directory part", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("cd /home/user/project/src", expand.expand("cd @%:h", "/cwd"))
        end)

        it("@%:t yields the filename", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("cat main.lua", expand.expand("cat @%:t", "/cwd"))
        end)

        it("@%:r strips the extension", function()
            ctx { ["%"] = "/home/user/project/src/main.c" }
            assert.equals("gcc /home/user/project/src/main.o", expand.expand("gcc @%:r.o", "/cwd"))
        end)

        it("@%:e yields the extension only", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("echo lua", expand.expand("echo @%:e", "/cwd"))
        end)

        it("@%:S shell-quotes a path with spaces", function()
            ctx { ["%"] = "/home/user/My Files/a b.txt" }
            assert.equals("cat '/home/user/My Files/a b.txt'", expand.expand("cat @%:S", "/cwd"))
        end)

        it("@%:q also shell-quotes a path with spaces", function()
            ctx { ["%"] = "/home/user/My Files/a b.txt" }
            assert.equals("cat '/home/user/My Files/a b.txt'", expand.expand("cat @%:q", "/cwd"))
        end)

        it("@%:p:h:t applies a chain left-to-right", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("echo src", expand.expand("echo @%:p:h:t", "/cwd"))
        end)

        it("@%:h:h:t chain drills into nested dirs", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("echo project", expand.expand("echo @%:h:h:t", "/cwd"))
        end)

        it("@%. resolves against the execution CWD, not the editor's", function()
            ctx { ["%"] = "/var/run/proj/src/main.lua" }
            assert.equals("cd ./src/main.lua", expand.expand("cd @%.", "/var/run/proj"))
        end)

        it("a bare modifier does not swallow the following literal", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("x ./src/main.lua then", expand.expand("x @%. then", "/home/user/project"))
        end)

        it("a bare ~ does not swallow the following literal", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("x ~/project/src/main.lua then", expand.expand("x @%~ then", "/cwd"))
        end)

        it("@%:p:h:. resolves chain against execution CWD", function()
            ctx { ["%"] = "/var/run/proj/src/main.lua" }
            assert.equals("cd ./src", expand.expand("cd @%:p:h:.", "/var/run/proj"))
        end)
    end)

    describe("filename modifiers: other tokens", function()
        it("@#:t applies to the alternate file", function()
            ctx { ["%"] = "/f.lua", ["#"] = "/etc/nginx/nginx.conf" }
            assert.equals("tail nginx.conf", expand.expand("tail @#:t", "/cwd"))
        end)

        it("@#7:h applies to buffer N's file", function()
            ctx { ["%"] = "/f.lua", ["#7"] = "/var/log/app/error.log" }
            assert.equals("cd /var/log/app", expand.expand("cd @#7:h", "/cwd"))
        end)

        it("@<cword>:t applies to a cursor word", function()
            ctx { ["%"] = "/f.lua", ["<cword>"] = "src/main.lua" }
            assert.equals("echo main.lua", expand.expand("echo @<cword>:t", "/cwd"))
        end)

        it("@<cWORD>:h applies to the WORD token", function()
            ctx { ["%"] = "/f.lua", ["<cWORD>"] = "/a/b/c" }
            assert.equals("ls /a/b", expand.expand("ls @<cWORD>:h", "/cwd"))
        end)

        it("@<cfile>:S shell-quotes a cursor file with spaces", function()
            ctx { ["%"] = "/f.lua", ["<cfile>"] = "/tmp/a b.txt" }
            assert.equals("cat '/tmp/a b.txt'", expand.expand("cat @<cfile>:S", "/cwd"))
        end)

        it("@#:. relativizes alternate against execution CWD", function()
            ctx { ["%"] = "/f.lua", ["#"] = "/var/run/proj/src/main.lua" }
            assert.equals("cd ./src/main.lua", expand.expand("cd @#.", "/var/run/proj"))
        end)
    end)

    describe("unsupported substitution modifiers", function()
        it("@%:s/a/b/ passes through verbatim, not partially expanded", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("cat @%:s/a/b/", expand.expand("cat @%:s/a/b/", "/cwd"))
        end)

        it("@%:gs/a/b/ passes through verbatim", function()
            ctx { ["%"] = "/home/user/project/src/main.lua" }
            assert.equals("cat @%:gs/a/b/", expand.expand("cat @%:gs/a/b/", "/cwd"))
        end)

        it("substitution on another token also falls back", function()
            ctx { ["%"] = "/f.lua", ["<cword>"] = "foo" }
            assert.equals("echo @<cword>:s/o/0/", expand.expand("echo @<cword>:s/o/0/", "/cwd"))
        end)

        it("substitution on bare @# falls back", function()
            ctx { ["%"] = "/f.lua", ["#"] = "/etc/nginx/nginx.conf" }
            assert.equals("cat @#:s/ngx/http/", expand.expand("cat @#:s/ngx/http/", "/cwd"))
        end)

        it("substitution on @#N falls back", function()
            ctx { ["%"] = "/f.lua", ["#3"] = "/var/log/app/error.log" }
            assert.equals("tail @#3:s/error/warn/", expand.expand("tail @#3:s/error/warn/", "/cwd"))
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
                ctx { ["%"] = "/f.lua" }
                assert.equals(case[3], expand.expand(case[2], "/cwd"))
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
                ctx { ["%"] = "/f.lua" }
                assert.equals(cmd, expand.expand(cmd, "/cwd"))
            end)
        end
    end)

    describe("new-token passthrough", function()
        it("unrecognized @<...> sequence passes through", function()
            ctx {}
            assert.equals("echo @<cfoo>", expand.expand("echo @<cfoo>", "/cwd"))
        end)

        it("@<cword> passes through when unset", function()
            ctx {}
            assert.equals("grep @<cword> .", expand.expand("grep @<cword> .", "/cwd"))
        end)

        it("@#N passes through when buffer N has no file", function()
            ctx { ["%"] = "/f.lua", ["#7"] = "" }
            assert.equals("cat @#7", expand.expand("cat @#7", "/cwd"))
        end)
    end)
end)
