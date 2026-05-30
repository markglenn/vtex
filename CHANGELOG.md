# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `Vtex.Tokenizer` — pure, stateless tokenizer turning a byte stream into typed
  tokens (`:text`, `:csi`, `:ss3`, `:osc`, `:esc`, `:invalid`) plus a leftover
  binary for incomplete sequences. DCS/APC/PM/SOS strings are rejected. The CSI
  body faithfully reproduces Williams' `csi_entry`/`csi_param`/`csi_intermediate`/
  `csi_ignore` states and "anywhere" transitions: parameter and intermediate
  bytes are collected into separate buffers (`{:csi, params, intermediates,
  final}`), and malformed sequences are silently discarded.
- `Vtex.Stream` — stateful streaming wrapper that buffers partial sequences
  across chunks and enforces a 256-byte buffer cap against memory-exhaustion
  input. `pending?/1` and `flush/1` let the caller resolve a standalone
  `Escape` keypress against an `ESC`-prefixed sequence using a read timeout.
- `Vtex.Input` — maps tokens to semantic events (keys, function keys, SGR,
  characters), recognising both CSI and SS3 forms of cursor/editing keys.
  `Alt`/`Meta`-modified keys (`ESC`-prefixed) surface as `{:alt, byte}`;
  `Shift`/`Ctrl`/`Alt`-modified arrows, navigation and function keys surface as
  `{:key, base, mods}`; characters are emitted as UTF-8 codepoints.
- `Vtex.SGR` — parses SGR parameter strings into structured colour/style
  attributes, including 256-colour and truecolor selectors.
- `Vtex.Mouse` — SGR mouse reporting: `enable/0`/`disable/0` control sequences
  and a decoder; events surface from `Vtex.Input` as `{:mouse, map}` with
  action, button, position and modifiers.
- `Vtex.Paste` — bracketed paste: `enable/0`/`disable/0` control sequences; the
  paste markers surface from `Vtex.Input` as `:paste_start` / `:paste_end`.
- `Vtex.Focus` — focus reporting: `enable/0`/`disable/0` control sequences; the
  terminal's focus changes surface from `Vtex.Input` as `:focus_in` /
  `:focus_out`.
- `Vtex.Input` also decodes Cursor Position Reports (`CSI r ; c R`) into
  `{:cursor_position, row, col}`.
- Output support (the library now handles both directions): `Vtex.SGR.encode/1`
  (attributes to an SGR sequence, including 256-colour and truecolor),
  `Vtex.Cursor` (movement, position, save/restore, visibility) and `Vtex.Screen`
  (clearing, the alternate buffer, scroll regions). All return iodata to write;
  the library still performs no IO of its own.
