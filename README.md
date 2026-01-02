<div align="center">

# cling.nvim

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/juniorsundar/cling.nvim/lint-test.yml?branch=main&style=for-the-badge)
![Lua](https://img.shields.io/badge/Made%20with%20Lua-blueviolet.svg?style=for-the-badge&logo=lua)

<img src="./assets/clinging.jpg" width="25%" />

</div>
<div align="center">
<br>
</div>


`cling.nvim` implements a customisable and thin CLI wrapper around executable binaries in Neovim.

It can be used to quickly execute terminal commands:
- without leaving the Neovim context via multiplexing or `Ctrl+z`, 
- without losing the text formatting of the command outputs,
- and also to interact with the output of those commands as a text-buffer.

The plugin can also be configured to wrap CLI commands that you commonly use (like `jj`, `docker`, etc.) and:
- automatically generate tab-completions in Neovim,
- implement custom keymaps for those wrapped CLI output buffers.

> [!NOTE]
> 
> Autogenerating tab-completions in Neovim is an experimental feature.
> 
> It may not work for all available CLI tools as there is no standard way to implement subcommands and completion functions in Bash.
> If such as instance is encountered, please raise an Issue ticket.

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
    "juniorsundar/cling.nvim",
    config = function()
        require("cling").setup({
            -- Add your wrappers here (see Configuration below)
            wrappers = {}
        })
    end,
}
```

## Usage

### The `Cling` Command

The plugin exposes the global `:Cling` command, which serves as a generic entry point for executing shell commands within the plugin's environment:

*   **`:Cling`**: Opens an input prompt to enter a shell command interactively.
*   **`:Cling with-env`**: Executes command with an `.env` file assigned interactively.
*   **`:Cling last`**: Executes the last executed command with `.env`.
*   **`:Cling -- <command>`**: Executes the command, treating everything after `--` as the command string. This defaults to executing in current working directory.

### Output Buffer Keymaps

When a command is executed, the output is displayed in a dedicated terminal-filetype buffer. The following default keymaps are available:

*   **`q`**: Closes the Cling window.
*   **`<CR>` (Enter)**: Smart file navigation. If the cursor is on a file path (common in `grep`, `ls`, or compiler output), pressing Enter will attempt to open that file in the previous window. It supports `file:line:col` formats to jump directly to the specific location.

## Configuration

You can define custom wrappers for your CLI tools in the `setup` function. Wrappers allow you to create specific Neovim user commands (e.g., `:JJ`, `:Docker`) with autocompletions that can either be derived from the CLI tool itself, or from the completion bash file.

### Completion Generation

`cling.nvim` provides **4 ways** to generate subcommands and completions for your wrappers:

1.  **Help Crawling (`help_cmd`)**:
    *   Recursively runs the binary with a help flag (e.g., `--help`) to parse subcommands and flags.
    *   *Best for:* Tools that don't provide bash completion scripts but have structured help output.
2.  **Completion Command (`completion_cmd`)**:
    *   Executes a specific command that outputs a Bash completion script, which is then parsed by the plugin.
    *   *Best for:* Modern tools that can generate their own shell completions (e.g., `cobra`-based CLIs).
3.  **Local Completion File (`completion_file`)**:
    *   Points to an existing Bash completion script on your local filesystem.
    *   *Best for:* Standard system tools where the completion file is already installed (e.g., `/usr/share/bash-completion/completions/`).
4.  **Remote Completion File (`completion_file` as URL)**:
    *   Points to a URL serving a raw Bash completion script. The plugin will `curl` this file.
    *   *Best for:* Tools where you want to fetch the latest completions directly from the repository without manual installation.

## Examples

### Wrapping Jujutsu (jj) with custom keymaps

This example shows how to wrap the [Jujutsu](https://github.com/martinvonz/jj) VCS and to implement a custom keymap to send the outputs of `jj show` to a quickfix list.

It uses the `completion_cmd` method to generate completions dynamically.

```lua
return {
    "juniorsundar/cling.nvim",
    config = function()
        local function strip_ansi(str)
            return str:gsub("\27%[[0-9;]*m", "")
        end

        local function get_file_from_line(line)
            local clean = strip_ansi(line)
            local file = clean:match "^Modified regular file (.*):$"
            if file then
                return file, "Modified"
            end
            file = clean:match "^Added regular file (.*):$"
            if file then
                return file, "Added"
            end
            file = clean:match "^Removed regular file (.*):$"
            if file then
                return file, "Removed"
            end
            file = clean:match "^Renamed .* to (.*):$"
            if file then
                return file, "Renamed"
            end
            local _, b = clean:match "^diff %-%-git a/(.*) b/(.*)"
            if b then
                return b, "Git Diff"
            end
            return nil
        end

        local function populate_quickfix(buf)
            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
            local qf_list = {}
            local current_file = nil
            local current_type = nil
            local last_was_gap = true

            for _, raw_line in ipairs(lines) do
                local line = strip_ansi(raw_line)
                local file, type = get_file_from_line(line)

                if file then
                    current_file = vim.trim(file)
                    current_type = type
                    last_was_gap = true
                elseif line:match "^%s*%.%.%.%s*$" then
                    last_was_gap = true
                elseif current_file then
                    local old, new = line:match "^%s*([0-9]*)%s+([0-9]*):"
                    if old or new then
                        if last_was_gap then
                            local lnum = tonumber(new) or tonumber(old) or 1
                            local text = line:sub((line:find ":" or 0) + 1)
                            table.insert(qf_list, {
                                filename = current_file,
                                lnum = lnum,
                                text = string.format("[%s] %s", current_type or "Change", vim.trim(text)),
                            })
                            last_was_gap = false
                        end
                    end
                end
            end

            if #qf_list > 0 then
                vim.fn.setqflist(qf_list, "r")
                vim.notify("Quickfix populated with " .. #qf_list .. " entries", vim.log.levels.INFO)
                vim.cmd "copen"
            else
                vim.notify("No file headers or hunks found", vim.log.levels.WARN)
            end
        end

        require("cling").setup {
            wrappers = {
                {
                    binary = "jj",
                    command = "JJ",
                    completion_cmd = "jj util completion bash",
                    keymaps = function(buf)
                        vim.keymap.set("n", "<C-q>", function()
                            populate_quickfix(buf)
                        end, { buffer = buf, silent = true, desc = "JJ: Move diffs to quickfix" })
                    end,
                },
            },
        }
    end,
}
```

</details>


### Different methods of generating tab-completion

Generating tab-completions can be achieved through following 4 methods:

```lua
wrappers = {
    -- Method 1: Recursive Help Crawling
    {
        binary = "docker",
        command = "Docker",
        help_cmd = "--help",
    },
  
    -- Method 2: Completion Command
    {
        binary = "jj",
        command = "JJ",
        completion_cmd = "jj util completion bash",
    },

    -- Method 3: Local File
    {
        binary = "git",
        command = "Git",
        completion_file = "/usr/share/bash-completion/completions/git",
    },

    -- Method 4: Remote URL (requires curl)
    {
        binary = "eza",
        command = "Eza",
        completion_file = "https://raw.githubusercontent.com/eza-community/eza/main/completions/bash/eza",
    },
}
```
