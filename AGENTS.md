# ZuzuScript Perl Runtime

This repository contains the Perl parser/runtime and command-line tools for
ZuzuScript. ZuzuScript scripts normally use `.zzs`; modules normally use
`.zzm`; syntax may include embedded POD. Comments use `//` and `/* ... */`.

Use Oxford English in documentation: mostly standard British English, with
`-ize` word endings.

## Relationship To Other Projects

`zuzu-perl` is the reference-style Perl implementation and one of the three
main runtimes, alongside `zuzu-rust` and `zuzu-js`. It consumes shared
resources through submodules:

- `stdlib` for shared modules, stdlib tests, fixtures, and test helpers.
- `languagetests` for language conformance tests.
- `docs/examples` and `docs/userguide` for examples and language reference.

The matrix project runs this runtime against the shared tests. The
webconsole is backed by this runtime. Do not refer to sibling repositories
with `..`; use the local submodules.

## Project Shape

- `bin/zuzu` is the main command-line runner.
- `bin/zuzu-tidy`, `bin/zuzu-highlight`, `bin/zuzudoc`, `bin/zuzuprove`,
  and `bin/zuzuzoo` are related tools.
- `lib/Zuzu/Lexer.pm`, `lib/Zuzu/Parser*.pm`, `lib/Zuzu/Runtime.pm`, and
  `lib/Zuzu/Value/` hold the language implementation.
- `lib/Zuzu/Module/` contains Perl implementations of runtime-supported
  modules.
- `lib/Zuzu/Web/PSGI.pm` supports ZuzuScript web apps through PSGI.
- `t/` contains Perl tests and wrappers for shared ztests.

## Runtime Rules

If a Pure Zuzu Module exists, the runtime must load, parse, and evaluate it
through normal ZuzuScript module loading. Do not add Perl-side shortcuts,
fast paths, or native replacements for Pure Zuzu Modules, especially
`std/path/*`, `std/path/z`, and `std/path/zz`.

Runtime-supported modules may be implemented in Perl when ZuzuScript has no
general facility for the required behaviour. `perl.zzm` is supported by this
runtime.

## Tests

Install dependencies with:

```bash
cpanm --installdeps -n .
```

Run the main suite with:

```bash
prove -lr t
```

The ztest wrapper runs scripts from `languagetests` and `stdlib/tests`.
Ztests emit TAP. A passing ztest should emit a valid plan, no `not ok`
lines, and exit with status zero.

When fixing tests, prefer fixing the parser/runtime. Do not modify `.zzs`
test scripts or fixture data. Modify `.zzm` modules only as a last resort
unless the module itself is the requested target.

## Zuzu::Tidy And Highlighting

`lib/Zuzu/Tidy.pm` formats ZuzuScript by tokenizing with `Zuzu::Lexer` and
validating with `Zuzu::Parser`. When changing language syntax, parser
behaviour, lexer token types, keywords, operators, delimiters, or literal
forms, check whether `Zuzu::Tidy` and `bin/zuzu-highlight` also need
updates.

Keep operator spacing tables, statement-boundary rules, paired-delimiter
handling, literal re-serialization, and highlighted token scopes in sync
with the grammar in `docs/userguide`. Add or update
`t/integration/tidy.t` and `t/integration/highlight-lexer-parser.t` when
those behaviours change.

## Style

Follow the repository's existing Perl style. For ZuzuScript code, use tabs
for indentation, spaces for alignment, One True Brace Style, uncuddled
`else`, whitespace around binary operators, and semicolons as terminators.
Keep ZuzuScript code lines under 80 columns where practical.
