# ztests gap analysis (2026-04-25)

This list focuses on combinations that are not currently covered (or are
only lightly covered) by the existing `t/ztests` suite.

1. File line iterator (`each_line`) feeding `std/db` prepared inserts in one flow.
2. `while` loop + `Path.next_line()` + transactional `DB.begin/commit` on chunk boundaries.
3. `for` loop over file lines with rollback-on-error behavior via `try/catch`.
4. `Path.glob()` result set piped into DB batch insert (`execute_batch`).
5. File read + CSV parse + DB insert + typed readback (`next_typed_dict`).
6. Directory iterator + DB upsert semantics (duplicate key handling).
7. DB iteration (`for row in stmt`) nested inside outer iterator from file or directory.
8. DB transaction behavior when loop exits via `last` or `return`.
9. DB transaction behavior when loop exits via thrown exception.
10. DB handle lifecycle with `defer` (auto close/rollback on scope exit).
11. DB + async process (`std/proc`) coordination in one test (write then external transform).
12. DB + async HTTP response ingestion and persistence.
13. DB + JSON encode/decode roundtrip of result rows.
14. DB + ZPath query operators (`@`, `@@`, `@?`) over query result payloads.
15. DB typed conversion edge cases for null/boolean/string numerics in one mixed row set.
16. `std/io` path semantics with Unicode filenames used as DB file path.
17. `std/io` binary mode + DB BLOB-ish value persistence/readback.
18. Concurrent writes (async tasks) against same temp DB handle.
19. Trait imported from module A, mixed into class in module B, consumed by module C.
20. Parent class imported from one module, trait from another, combined subclass in third module.
21. Diamond inheritance-ish trait mixin conflicts resolved with explicit override.
22. `super()` dispatch from class method to trait-provided method loaded cross-module.
23. Static field/method inheritance interactions with imported traits.
24. Trait method calling `super()` where superclass method comes from imported module.
25. Nested class definitions inside imported module used with external traits.
26. Runtime type checks (`does`, `instanceof`, `can`) across module boundaries.
27. Class field accessors (`with get,set`) when trait mutates inherited field from parent module.
28. Dynamic member call on trait method name resolved at runtime across modules.
29. Module aliasing + OOP: alias-imported class constructor and static members.
30. `from import *` collision resolution when two modules export same trait/class names.
31. Import cycle involving trait module and class module (error quality + determinism).
32. Optional import fallback path with class/trait feature detection.
33. Async function inside class method that also uses inherited trait methods.
34. Exception line-number metadata across imported module boundaries.
35. Throwing custom exception class declared in one module, caught as parent in another.
36. `switch/case` dispatch over enum-like class constants imported from module.
37. `for-else` semantics when iterator is DB statement object that errors mid-stream.
38. `while` + `continue` + `defer` interaction (defer should still execute).
39. `next`/`last` behavior in nested loops where inner loop is object iterator.
40. Template engine (`std/template/z`) rendering values fetched from DB rows.
41. Template rendering with trait-backed object methods and inherited accessors.
42. HTTP response body -> JSON parse -> ZPath query -> template render pipeline.
43. HTTP request builder + URL helper + query dict with non-ASCII keys/values.
44. HTTP cookie jar persistence across multiple async requests in one scenario.
45. HTTP timeout/retry behavior composed with `std/task all` concurrency primitive.
46. HTTP response header normalization combined with case-insensitive dict access.
47. XML parse + ZPath query (or path module) integration in one test flow.
48. YAML/TOML/INI config load selecting DB/HTTP behavior branches.
49. `std/config` + environment overrides + module import path behavior.
50. `std/eval` evaluating code that imports modules and defines classes/traits.
51. `std/eval` sandbox/error behavior when evaluated code throws inside async block.
52. `std/cache/lru` wrapping DB-backed lookup function under concurrent async calls.
53. `std/defer` in async function with awaited DB/HTTP operations.
54. `std/proc` pipeline output streamed line-by-line into DB inserts.
55. `std/proc` stderr handling plus exception mapping in mixed success/failure pipelines.
56. Digest modules (`md5/sha/crc32`) over large file chunks read with `std/io` iterators.
57. `std/archive` extraction to temp dir then glob+parse+insert workflow.
58. Binary string boundaries combined with file IO and DB typed retrieval.
59. Regex captures in loop used to construct typed class instances from file records.
60. End-to-end multi-module integration test combining import aliasing, inheritance,
    traits, async IO, DB persistence, and structured assertions.
