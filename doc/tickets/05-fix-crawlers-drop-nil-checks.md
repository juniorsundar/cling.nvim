# 05: Fix crawlers to use command_node.new() and drop defensive nil-checks from find()

**What to build:** Both crawlers — `help_crawler` and `completion_script_crawler` — replace all raw `{ flags = {}, subcommands = {} }` literals and bare `{}` children with `command_node.new()`. This closes the hidden construction sites that bypass the constructor, making the shape invariant universal: every `CommandNode` in the system, whether constructed by parsers, crawlers, generator, or loaded from disk, has `flags` and `subcommands`. With the invariant in place, `find()` drops all defensive nil-checks on `node.flags` and `node.subcommands` — the fields are guaranteed to exist. All existing tests pass without the nil-checks.

**Blocked by:** 04 (Extract find() into command_node)

**Status:** done

- [x] `help_crawler` uses `command_node.new()` for all node construction (including the depth-limit sentinel)
- [x] `completion_script_crawler` uses `command_node.new()` for root and all child node construction (including depth-boundary children that were previously bare `{}`)
- [x] No raw `{ flags = {}, subcommands = {} }` or bare `{}` literals remain in any crawler file
- [x] `find()` has no defensive nil-checks on `node.flags` or `node.subcommands`
- [x] `find()` safely iterates `node.flags` and `node.subcommands` without nil-checks
- [x] All existing `find()` tests pass without nil-checks
- [x] All existing tests pass
