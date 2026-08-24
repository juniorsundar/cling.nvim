# Changelog

## [0.6.0](https://github.com/juniorsundar/cling.nvim/compare/v0.5.0...v0.6.0) (2026-08-24)


### Features

* Add `expand.lua` to handle vim-command expansion ([d887afc](https://github.com/juniorsundar/cling.nvim/commit/d887afc8280b8b0536f3f365957062559a2f817a))
* **expand:** Add filename mods and chains support ([856d504](https://github.com/juniorsundar/cling.nvim/commit/856d50407020d399d905584bf8af2864f0d3d786))
* **expand:** Add non-modifier tokens support ([0040b5e](https://github.com/juniorsundar/cling.nvim/commit/0040b5e2543e6a3d68de3134f026a0ac9a729919))


### Bug Fixes

* Padding on status/sign/foldcolumn was pushing things out of view ([e1fa6e7](https://github.com/juniorsundar/cling.nvim/commit/e1fa6e76d62b9eb02f3f0cfd775c8fab06f9941a))


### Code Refactoring

* extract `command_node` -&gt; universal node invariant ([a78685b](https://github.com/juniorsundar/cling.nvim/commit/a78685b2e30fa0c5232807e5f7065ca9730de428))
* **navigation:** extract jump_to and export from executor into navigation module ([696fd87](https://github.com/juniorsundar/cling.nvim/commit/696fd87ec6750e1ede677fa86bf7a389d6ede9ad))


### Tests

* **core:** add teardown-on-close test coverage for all close paths ([551b03b](https://github.com/juniorsundar/cling.nvim/commit/551b03b757ab989739d4297f14f39c9224778286))

## [0.5.0](https://github.com/juniorsundar/cling.nvim/compare/v0.4.0...v0.5.0) (2026-04-25)


### ⚠ BREAKING CHANGES

* **history:** Separate history by working directory (opt-out in config)

### chore

* release 0.5.0 ([af1c0df](https://github.com/juniorsundar/cling.nvim/commit/af1c0dfabcc757b93a0775e0ef2bee6a30928859))


### Features

* `no_history` for wrapped CLI commands ([84ea666](https://github.com/juniorsundar/cling.nvim/commit/84ea6661e0474960e6ba9d6ed0c2590fb355f059))
* **cling:** &lt;C-l&gt; Keymap for clearing input ([59773f3](https://github.com/juniorsundar/cling.nvim/commit/59773f3a314eac49234d649ed554ff043a91d6a7))
* **history:** Separate history by working directory (opt-out in config) ([acf125d](https://github.com/juniorsundar/cling.nvim/commit/acf125d417475943c287d52d9844bfa2cd2ed846))
* Implement `on_close` hook ([be70404](https://github.com/juniorsundar/cling.nvim/commit/be704047de41d05bd312bc6f7dfbf7f8da487b6a))
* Set `cwd` for wrapped CLI commands ([6d74f0b](https://github.com/juniorsundar/cling.nvim/commit/6d74f0b8b841777e7cd56d58b16d800e475d4a88))


### Bug Fixes

* **ci:** handle SIGHUP crash on Windows nightly in test runner ([d9339b8](https://github.com/juniorsundar/cling.nvim/commit/d9339b8c4cdf07d69f95ef4ba40da49d64a533b7))

## [0.4.0](https://github.com/juniorsundar/cling.nvim/compare/v0.3.0...v0.4.0) (2026-03-13)


### Features

* **export:** Export output from Cling to a .log file ([515c78a](https://github.com/juniorsundar/cling.nvim/commit/515c78a9f3d980de615f988988449692599fb276))
* **opts:** `close_on_exit` for wrapping TUIs ([60be3ad](https://github.com/juniorsundar/cling.nvim/commit/60be3adb1f068ebf4e4bea6efeabd380e386aa77))
* **smods:** Supports :vert, :tab, etc. ([40944a9](https://github.com/juniorsundar/cling.nvim/commit/40944a96d1e352da91226b067352b8c78bdc452d))

## [0.3.0](https://github.com/juniorsundar/cling.nvim/compare/v0.2.0...v0.3.0) (2026-01-23)


### Features

* additional vim.fn.input pcall, with `not string_name` `string_name ([8910c71](https://github.com/juniorsundar/cling.nvim/commit/8910c7172891f8579692e47d66adbbc276a0c41e))
* quietly handle &lt;C-c&gt; ([bf988c9](https://github.com/juniorsundar/cling.nvim/commit/bf988c95d802ccd960f7ba9217eb7ad839cb5391))
* quietly handle &lt;C-c&gt; ([daf8995](https://github.com/juniorsundar/cling.nvim/commit/daf899567026547833d1f4bae5b1e3d53220818e))


### Tests

* Fixed failing test with quiet cancelling ([d4ffcea](https://github.com/juniorsundar/cling.nvim/commit/d4ffcea6992dafd98393c19c0693f9e13659849c))


### Continuous Integration

* Implement release-please ([6d49fb4](https://github.com/juniorsundar/cling.nvim/commit/6d49fb4c60d5125256645852d094b5d5ff6b41be))
