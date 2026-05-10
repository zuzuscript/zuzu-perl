# ZuzuScript Perl Runtime

This repository contains the Perl parser/runtime and command-line tools for
ZuzuScript. ZuzuScript scripts normally use `.zzs`; modules normally use
`.zzm`; syntax may include embedded POD. Comments use `//` and `/* ... */`.

Use Oxford English in documentation. Prefer standard British English with
`-ize` word endings.

## Split Repository Layout

Shared ZuzuScript resources live in submodules:

- `stdlib/modules` contains the Pure Zuzu Modules and POD stubs for
  runtime-supported modules.
- `stdlib/tests` contains standard-library ztests.
- `stdlib/test-modules` contains test helper modules.
- `stdlib/test-fixtures` contains standard-library fixtures.
- `languagetests` contains language-level ztests.
- `docs/examples` and `docs/userguide` are documentation submodules.

Do not refer to sibling repositories with `..`. If this repository needs
shared files from another repository, add them as a git submodule.

## Standard Library Rules

If a Pure Zuzu Module exists, the runtime must load, parse, and evaluate it
through normal ZuzuScript module loading. Do not add Perl-side shortcuts,
fast paths, or native replacements for Pure Zuzu Modules, especially
`std/path/*`, `std/path/z`, and `std/path/zz`.

Runtime-supported modules may be implemented in Perl when ZuzuScript has no
general facility for the required behaviour. `perl.zzm` is supported by this
runtime.

## Tests

Run the main suite with:

    prove -lr t

The ztest wrapper runs scripts from `languagetests` and `stdlib/tests`.
Ztests emit TAP. A passing ztest should emit a valid plan, no `not ok` lines,
and exit with status zero.

When fixing tests, prefer fixing the parser/runtime. Do not modify `.zzs`
test scripts or fixture data. Modify `.zzm` modules only as a last resort.

## Style

Follow the repository's existing Perl style. For ZuzuScript code, use tabs
for indentation, spaces for alignment, One True Brace Style, uncuddled
`else`, whitespace around binary operators, and semicolons as terminators.
Keep ZuzuScript code lines under 80 columns where practical.
