# 11: Passthrough & escape guarantee matrix (regression lock)

**What to build:** The zero-shell-casualty guarantee is the load-bearing
property of this design: the entire pre-existing behavior space of Cling
commands is unchanged unless a recognized marked token appears. This slice
locks that guarantee with a table-driven regression suite covering every
class of input that must pass through verbatim, once the full token and
modifier space exists. It asserts that a command line with no recognized
marked token is returned byte-identical to its input.

**Blocked by:** 09 (Non-modifier tokens), 10 (Filename modifiers — for the
substitution-modifier fallback case)

**Status:** complete

- [x] Table-driven tests assert passthrough for: bare `@`; `@@` (→ single `@`); `@` at end of input; `@x` (marker + unrecognized char); `me@example.com` and similar incidental `@`; unmarked `%`, `#`, `#N`, `<`, `>`; backtick command substitution
- [x] Tests assert shell-idiom inputs are untouched: `printf '%s\n' hi`, `make x # note` (comment), `sort < a > b` (redirection), ``echo `date` `` (backtick substitution)
- [x] Test asserts `@%:s/a/b/` and `@%:gs/a/b/` (unsupported modifiers) pass through verbatim — the marked site is not partially expanded
- [x] Test asserts a command line containing no recognized marked token is returned byte-identical to its input
- [x] All earlier token/modifier behavior still passes — no regressions introduced by the matrix