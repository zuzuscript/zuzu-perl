# Native ztests coverage matrix

This directory contains runtime-semantic coverage in native `.zzs`
programs. The matrix below tracks feature ownership at a high level.

## Discovery and harness notes

- `t/99-ztests.t` discovers only `*.zzs`, so ztest files must use the
  `.zzs` extension.
- Run `perl t/ztests/coverage-audit.pl` for a lightweight check of:
	- documented operator and keyword tokens,
	- expected operator ztest files,
	- token presence in native ztests.
- Regenerate the implementation matrix JSON (Perl + Rust + JavaScript
  runs) with
  `perl t/ztests/generate-implementation-matrix-json.pl`.
- Regenerate the browser-based zuzu-js matrix JSON with
  `extras/zuzu-js/bin/generate-browser-implementation-matrix-json`.
  Add `--manual-browser` to print a local URL and run the browser tests
  in your own browser.
- Regenerate the implementation matrix markdown from those JSON files with
  `perl t/ztests/regenerate-implementation-matrix.pl`.

## Coverage matrix (phase 0 + phase 1 + phase 2 + phase 3 + phase 4 + phase 5)

| Area | Native ztests | Status |
| --- | --- | --- |
| Harness discovery | `t/99-ztests.t`, `t/ztests/control/basic.zzs` | ✅ active |
| Operators (phase 1 scaffold) | `t/ztests/lang/operators/*.zzs` | ✅ active |
| Core collections | `t/ztests/collection/*.zzs` | ✅ active |
| Core number/string | `t/ztests/number/ops.zzs`, `t/ztests/string/*.zzs` | ✅ active |
| Type checks | `t/ztests/types/*.zzs` | ✅ active |
| OOP basics | `t/ztests/oo/basic.zzs` | ✅ active |
| Control flow basics | `t/ztests/control/*.zzs` | ✅ active |
| Keywords parity suite | `t/ztests/lang/keywords/*.zzs` | ✅ active |
| Control-flow parity suite | `t/ztests/lang/control/*.zzs` | ✅ active |
| Functions parity suite | `t/ztests/lang/functions/*.zzs` | ✅ active |
| OOP parity suite | `t/ztests/lang/oop/*.zzs` | ✅ active |
| Builtin subclassing parity | `t/ztests/lang/oop/builtin-subclassing.zzs` | ✅ active |

## Phase 4 integration policy

- Integration `.t` files now keep parser/runtime embedding smoke checks,
  module/filesystem loading checks, and compile-time parser-specific
  negative assertions.
- Runtime-semantic matrices for operators, function signature behavior,
  and OOP dispatch are owned by native ztests under `t/ztests/lang/`.

## Phase 5 status

- Integration semantic duplication was slimmed to parser/runtime embedding smoke checks in `t/integration/runtime-operators.t` and runtime-policy smoke checks in `t/integration/missing-core-features.t`.
- Native keyword runtime coverage now includes explicit `warn` parsing coverage in `t/ztests/lang/keywords/runtime-debug.zzs` (kept in an unreachable branch to avoid TAP output pollution).

## TEST1 coverage map (2026-03-21)

| Capability | Existing owner(s) | Gap status | TEST1 action |
| --- | --- | --- | --- |
| Parser error handling | `t/integration/parse.t`, `t/integration/error-metadata.t` | Needed focused malformed-input edge cases | Added `t/integration/test1-foundation-gaps.t` parser error table with compile code/file/message checks. |
| Coercion corners | `t/ztests/string/ops.zzs`, `t/ztests/number/ops.zzs` | Needed deterministic cross-run semantics fixtures | Added deterministic fixture-driven coercion coverage in `t/fixtures/semantics/language-core.json` exercised by `t/integration/test1-foundation-gaps.t`. |
| Runtime exception taxonomy | `t/integration/error-metadata.t` | Needed explicit edge-path runtime checks | Added runtime exceptions for non-callable invocation and invalid set coercion in `t/integration/test1-foundation-gaps.t`. |
| Module load failures | `t/integration/import-features.t`, `t/integration/runtime-forbid.t` | Needed explicit missing-module and builtin load failure checks | Added targeted module resolution and builtin-package failure assertions in `t/integration/test1-foundation-gaps.t`. |
| Deterministic semantics fixtures | none | Missing fixture set for cross-implementation parity | Added `t/fixtures/semantics/language-core.json` and deterministic fixture runner loop in `t/integration/test1-foundation-gaps.t`. |
