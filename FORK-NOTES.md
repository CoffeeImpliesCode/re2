# FORK-NOTES — the decisions, what each cost, and what is still open

This is the worker's record. `README.md` says what deviates from upstream,
`README.zig.md` says what the interface is, `CHANGELOG.md` says what changed and
when. This file says **why**, and — the part that matters most — **what is still
wrong, unproven or undecided**.

**Everything PENDING-VERIFICATION is collected in one place at the end.** Nothing
in this package has been built, tested, smoked, installed or fetched by this role.

---

## 1. Why a C bridge at all

`addTranslateC` translates **C**. RE2 at this pin is C++17 with a class, an
`std::string`, an `absl::string_view` and name-mangled linkage
(`vendor/re2/Makefile:52` sets `-std=c++17`). There is no route from a translated
upstream C++ header to a Zig module, and writing one would mean either a
hand-maintained declaration set that drifts from upstream or a build-time
`bindgen`, which would make the package's interface a function of the toolchain's
version rather than of its source.

So the C surface a Zig caller needs is **written once, by hand**, as
`zig/bridge.h` — plain C99 with `extern "C"` guards, so a C translator can read
it and a C++ compiler can compile it — and `zig/bridge.cc` implements it against
the compiled upstream types.

**What that costs, stated plainly.** The bridge is 22 units of surface that a
consumer could have got by including an upstream header, and it can drift from
upstream on a re-sync without anything noticing. The mitigation is that every
declaration in it is a **thin named wrapper around one upstream call on one real
RE2 type**, and each one carries its upstream line reference in a comment. A
re-sync step that changes an upstream signature changes the line the wrapper calls
next to it.

**What the bridge deliberately does not do:** match a pattern, rewrite a match or
escape a metacharacter. Every answer this package publishes comes from
`RE2::Compile`, `RE2::Match`, `RE2::Rewrite`, `RE2::QuoteMeta` and
`RE2::CheckRewriteString`. The bridge adds a *shape* — a C struct, a status enum,
two-pass buffers — and no behaviour.

---

## 2. The tri-state `Flag`, and the inversion a `bool` would have caused

**The single most likely thing for a caller to get wrong, and the reason it
cannot be got wrong is a design decision rather than a comment.**

Upstream's `RE2::Options` does **not** default its booleans to false. The
constructor initialiser list at `vendor/re2/re2/re2.h:678-692` sets:

```
log_errors_(true),      // :683
case_sensitive_(true),  // :688
```

and every other boolean to `false` (`:681-687`, `:689-691`).

A facade field typed `bool` with a `false` default therefore means **false**, not
"upstream's default". A caller writing

```zig
.{ .log_errors = false, .case_sensitive = false }
```

"to be explicit" would have **inverted** both relative to `.{}`: logging off
instead of on, and case folding on instead of off. And the same spelling would
have been *correct* for the other eleven booleans, which really do default to
false. A caller who learned the field type from one field and applied it to
another would get a silently wrong engine, on exactly the two options where
being wrong changes results.

`Flag { @"default", on, off }` makes "leave it alone" expressible, which is what
a zero-initialised struct has to mean. `.@"default"` reaches upstream's setter
**not at all**; `on`/`off` are `set_<name>(true)`/`set_<name>(false)`. Any other
ordinal is `InvalidArgument`, checked rather than clamped.

**What it cost.** A tri-state is more verbose than a bool at a call site that
genuinely wants a bool, and `Options` has thirteen fields where a bool struct
would have read more plainly. Accepted: the alternative was a default that lies
about two of thirteen fields, and the field list is documented with upstream's
default printed next to each entry in `README.zig.md`.

`consumer/src/main.zig`'s invalid-pattern case demonstrates it: it sets
`log_errors = .off` deliberately, because `.{}` would have Abseil-logged the parse
failure to stderr (`re2/re2.cc:241-243`) before the program said anything.

---

## 3. The offset-bound check the bridge adds, and why upstream cannot do it

**Upstream folds a bad offset pair into an ordinary non-match.** `RE2::Match`:

```cpp
if (startpos > endpos || endpos > text.size()) {
  if (options_.log_errors())
    ABSL_LOG(ERROR) << "RE2: invalid startpos, endpos pair. [...]";
  return false;
}
```

(`vendor/re2/re2/re2.cc:670-677`)

`false` is also what it returns for a subject that simply does not match. **Upstream
cannot distinguish a programming mistake from a well-behaved decline**, and it does
not try to: the log line is the only difference, and a library is not entitled to
make a `bool` return value mean two things.

So `re2br_match` rejects the pair **before the engine runs**, as
`RE2BRIDGE_INVALID_ARGUMENT`, which the facade maps to `OffsetOutOfRange`. The
facade checks the same pair *again* in `Regex.match` and `Regex.extract` before
calling the bridge, so the common path never reaches C at all.

**The bound is upstream's and is not tightened.** `endpos > text.size()` means
`endpos == text.size()` is **in range**. A check written as `end >= subject.len`
would refuse a legitimate full-subject search. `consumer/src/main.zig`'s
offset-refusal case checks all three: `end` one past the end is refused, `start >
end` is refused even when both ends are inside the subject, and `end ==
subject.len` must **not** be refused.

**What it cost.** One error name that is not upstream's, and a caller who wants
upstream's exact fold-the-two-together behaviour cannot get it through the facade
(it can, through `re2.c`). Both are deliberate and both are stated in
`README.zig.md`.

---

## 4. `zig/bridge.h` includes `<stddef.h>` and `<stdint.h>` and nothing else

**This is a CONSTRAINT, and a future edit must respect it.** It is not a style
preference.

The runtime loader's extern sweep enumerates what the translated header declares
and resolves each name through the platform loader. Every name in
`zig/bridge.h` is a `re2br_*` function or an `RE2BRIDGE_*` constant **as long as
the header reaches no libc header**. The moment it reaches `<string.h>`,
`<stdlib.h>` or `<math.h>`, that sweep has to grow a `libc_noise` list of names it
must *not* try to resolve from the provider — and that list is a measured file
that has to be kept in step with the header by hand.

The second consequence, stated in the header itself: **it names no upstream
type.** `RE2::Options` reaches the caller as `Re2BridgeOptions`,
`absl::string_view` never appears, and the translated Zig module is therefore a
description of *this* surface rather than of an upstream one that could change
under it. A bridge header that named `RE2` would pin the Zig side to upstream's
class layout.

**What a future edit must not do:** add a libc include "just for `strlen`", and
add a libc function call "just for convenience". Both are how the sweep's
assumption is broken, and both are cheap to do by accident.

---

## 5. A failed pattern still yields a live handle, and `re2br_match` refuses it

**`RE2BRIDGE_BAD_PATTERN` is the one status that still hands back a live handle,
and that is upstream's model rather than a convenience.**

A rejected pattern leaves an `RE2` whose `ok()` is false and whose `error()` is
populated — and `error()` is an accessor **on that object**
(`vendor/re2/re2/re2.h:314-316`). Destroying the object at the bridge would
destroy the one explanation upstream offers, so the bridge does not.

The Zig facade then reads that message into the caller's buffer and frees the
handle **before returning `error.InvalidPattern`** (`zig/widthed.zig`,
`compileInto`). So:

* `Regex.compileInto(pattern, options, message)` is the entry point that carries
  the reason.
* `Regex.compile` is `compileInto` with an empty buffer, and therefore
  **discards** the reason. It is not a smaller `compileInto`; it is the one with
  nothing to show.
* **No caller ever holds a failed handle** on the error path, so there is no
  handle to remember to free.
* `re2br_match` refuses the handle outright, so a refused pattern cannot be
  matched with. `re2br_regex_group_count` answers -1 for it, because the
  constructor resets `num_captures_` to -1 and assigns the real count only on
  success (`re2/re2.cc:223`, `:276`) — and the facade refuses the -1 and reports
  0 rather than handing back a negative count.

**The cost, stated because it is real.** The message has to be copied before the
object dies, so `compileInto` writes into a **caller-owned buffer with no length
returned**: it copies `@min(text.len, message.len)` bytes and writes no
terminator. A caller who wants the length has to size a buffer it knows is larger
or pre-fill with a sentinel and scan. That is a rougher interface than a
`![]const u8` return, and it was chosen because the alternative — returning a
pointer borrowed from the handle — is a dangling pointer on the very path a
caller is most likely to hold onto while formatting an error message.
`consumer/src/main.zig` does the sentinel scan and states why its bound is safe.

---

## 6. Only 8-bit code units exist, and why no 16/32-bit instantiation is offered

**The pcre2 fork in this workspace is genuinely generic over its code unit
because upstream pcre2 ships three libraries.** RE2 at this pin does not:

* its subject is an `absl::string_view` (`re2/re2.h:585`),
* `re2::StringPiece` is a plain alias for it (`re2/stringpiece.h:14`),
* and `RE2::Match` bounds its offsets against `text.size()` with byte slicing
  (`re2/re2.cc:670-681`).

There is exactly one unit at this pin and it is the byte. A 16- or 32-bit RE2
would need a port of the engine, not a different argument to this module.

**So `Width(code_unit)` keeps the shape — one `Width` that every offset is
counted in, with the unit type carried by the subject slice and never by the
offset — and refuses any width the compiled core cannot serve**, with a
`@compileError` naming the reason rather than leaving a caller to discover it as
a link error. The refusal is on `@sizeOf(code_unit) != 1`, which is the honest
test: an RE2 subject is a byte string.

**What it cost.** A generic that always resolves to one instantiation is a shape
with no second case behind it, and the compiler will not warn about a generic
that was never needed. The alternative — deleting `Width` and hard-coding `u8` —
would have been less code and would have made the *decision* invisible: a later
reader could not tell whether a 16-bit surface was considered and rejected or
simply not thought about. The compile error is the record.

**There is deliberately no code-unit-to-byte helper.** At this pin it would be
the identity function, and an identity function wearing a name is an invitation
to treat it as a conversion later.

---

## 7. `wasm32-wasi`: the provider question, and what each route does there

`wasm32-wasi` is a supported target for this SDK and **stays one**.

* **The facade's surface is not reduced for WASI**, and nothing in
  `zig/root.zig` or `runtime/graph.zig` answers a WASI request differently from a
  linked one. The runtime-loading refusal below is a property of the *loader* —
  WASI has no `dlopen` — not of the library's capability.

**What is observed, 2026-10-05, and corrects an earlier claim in this section.**
This bullet previously said the linked configuration on WASI "is exactly as
complete there as anywhere else". That was written before any gate ran, and it
is wrong as a statement about *compilation* on the pinned toolchain:
`zig build check -Dtarget=wasm32-wasi` exits 1 with 19 errors. The library
source is not what fails — the C++ closure is upstream's and the facade's Zig
code is this fork's, and neither is implicated. The causes are
`_LIBCPP_HAS_THREADS 0`, `_LIBCPP_HAS_FILESYSTEM 0`, and a `poison.cc` defect on
a platform upstream does not list; README §3's "Two of the six do not compile
here, and why" gives each with its citation. The target **stays in the matrix
and stays a supported target**: an unbuildable cell on one toolchain is an
observation about that toolchain, and dropping the target would make it
unobservable rather than fix it.

* **Runtime loading is refused at run time** with `error.UnsupportedTarget`,
  because WASI has no `dlopen`. `runtime/loader.zig` has a `NoLoader` platform
  layer whose `open` returns exactly that, and it is an honest refusal rather
  than a fallback to a linked copy: no provider is opened and nothing is
  published.

**That refusal is not a reason to exclude the target.** A loader that silently
linked the library instead would mean the same `-Druntime=true` produced two
different behaviours on two targets, and a caller could not tell which one it
got.

**The WASI sysroot is SDK-owned.** Headers and C/C++ runtime archives come from
an installed SDK; this package installs none of them and redistributes none.

---

## 8. Open risk — `zig fetch` and the tree's one symlink

**UNOBSERVED. Do not assume either outcome.**

`vendor/re2/python/LICENSE` is a **symlink** to `../LICENSE`. It is the **only**
symlink in either vendored tree — 139 entries under `vendor/re2`, of which 138
are regular files and this is the one that is not.

This matters because `build.zig.zon`'s `.paths` names `vendor` as a whole
directory, and Zig materialises a package by hashing its contents. **How Zig
0.16.0 treats a symlink inside a materialised package has not been observed
here.** There are three possible behaviours and none has been checked:

1. it follows the link and stores the target's bytes;
2. it stores the link target string as the file's content;
3. it refuses the package outright.

**The gate that would settle it** is an actual `zig fetch` of this package by a
consumer — the per-consumer-package gate in this workspace's `AGENTS.md`. Until
that runs, this is an open question and no sentence in this repository may claim
the fetch works or that it fails.

**The remedy, so the risk carries one.** If the fetch turns out to fail, or to
materialise a `LICENSE` that is the text `"../LICENSE"` rather than the licence,
**the fix is a build-file change that copies that one file instead of symlinking
it** — it is a change to how this package *lays down* one file, not a licence
change and not a provenance change. The file's bytes stay upstream's and stay in
`UPSTREAM.sha256`; only the packaging step differs. **It is not a licence or
provenance question, and it must not be answered by re-pinning or re-deriving
anything.**

---

## 9. Open constraint — an upstream `.gitignore` swallows four vendored files

**A root `.gitignore` CANNOT fix this, and the reason is precedence.**

`vendor/re2/.gitignore` is upstream's own file and contains `benchlog.*` among
its rules. Git honours a `.gitignore` at any directory level, and the four files

```
vendor/re2/benchlog/benchlog.c2
vendor/re2/benchlog/benchlog.mini
vendor/re2/benchlog/benchlog.r70
vendor/re2/benchlog/benchlog.wreck
```

match it. They are upstream's committed benchmark corpora, retained material
recorded in `UPSTREAM.sha256` group F.

**Why the root `.gitignore` cannot rescue them.** Gitignore precedence is "patterns
in lower-level files override those in higher-level files". `vendor/re2/.gitignore`
is **deeper** than the fork's root `.gitignore`, so the vendored rule wins and a
negation in the root file does not override it. This was established with
`git check-ignore --no-index -v` in a scratch tree, not assumed.

**The directory itself is fine.** `benchlog.*` does not match the basename
`benchlog`, so git always descends into the directory; only the four files inside
are affected, and `benchplot.py` and `mktable` are not matched.

**The mechanism that works is a one-time force-add:**

```
git add -f vendor/re2/benchlog
```

**The directory, not four paths** — one command pulls the four files in. Once a
path is tracked, `.gitignore` stops applying to it for subsequent commits, which
is what makes the single action sufficient.

**Why the root `.gitignore` keeps its negation lines anyway.** They are a hedge
for tools that read the root file alone and do not descend. They are not the fix
and this file does not claim they are.

**`vendor/re2/.gitignore` is upstream bytes and this tree is pristine, so it must
not be edited.** That is the whole constraint.

**Horizon learning — condition, symptom, fix, targets.**

* **Condition:** vendoring an upstream tree *whole* under a subdirectory whose own
  `.gitignore` contains a broad rule that matches committed upstream files.
* **Symptom:** the files are present in the working tree and recorded in the
  integrity manifest, but are **never committed**. The symptom is not a build
  failure — it is a package that is correct on the machine that vendored it and
  broken for everyone who fetches it, and it surfaces as a correctly fetched
  package **failing its own digest check** because four of the paths in
  `UPSTREAM.sha256` are missing. Nothing in the vendoring step says so.
* **Fix:** force-add the affected directory **once**. Never edit the upstream
  `.gitignore`. Confirm with `git check-ignore --no-index -v <path>` that the
  deeper rule is the cause before concluding anything, and record which command
  was run.
* **Targets bound:** any SDK in this workspace that vendors an upstream tree whole
  under a subdirectory rather than laying it down at the package root. Without
  the force-add those four files are never committed **even though `.paths` names
  `vendor` and the manifest records them**.

---

## 10. The C++ runtime on the ELF shared route, and the single-owner reason

`-Dlinkage=dynamic` on an ELF target delivers a **fourth** artifact,
`libre2cpp.so.0`, compiled from the pinned compiler's own shipped libc++,
libc++abi and libunwind sources by `build_support/cpp_runtime.zig`.

**The reason is single ownership of the C++ runtime across images.** A
compiler-provided *static* libc++ archive is built with hidden exports and its own
copy of every typeinfo and locale facet. Three images each carrying a private
copy give one program three definitions of the same inline functions, and both
definitions are `WEAK`/`DEFAULT`, so the dynamic linker is free to bind one
image's caller to another image's copy. RE2's public signatures are full of C++
types across that boundary — `RE2::Match` takes an `absl::string_view`
(`re2/re2.h:563-589`) and `RE2::Options` puts `std::string`-adjacent state behind
setters (`re2/re2.h:673-692`) — so the boundary is crossed in both directions.

Upstream avoids the question by having one build and one runtime per
configuration: `vendor/re2/CMakeLists.txt:15` has
`option(BUILD_SHARED_LIBS … OFF)` and one `re2` target. This graph builds three
artifacts and so needs the same single-owner answer.

**Why the file list was not re-derived.** It is transcribed from the pinned
compiler's `src/libs/libcxx.zig`, from the s2geometry fork's transcription of the
same file for the same compiler. A fork that re-guessed the list would be
compiling something **other than the runtime the rest of the graph is compiled
against**, which is a worse outcome than citing a sibling's derivation. The
provenance note is kept even though the artifact's name changed from `s2cpp` to
`re2cpp`.

**What it is not:** a patched compiler, a vendored compiler source, or a modified
compiler installation. No compiler source is copied into this repository and none
is edited. Only the **artifact name** (`re2cpp`) and the **licence prefix**
(`share/licenses/re2/`) are this package's own decisions.

**Its file version is the compiler's 0.16.0, not RE2's.** The object *is* the
compiler's libc++, so a consumer pins its soname exactly as it does for the other
three artifacts. `static`, `wasm32-wasi`, Darwin and Windows compile no such
object at all.

---

## 11. No system-library mode, and why the obvious one cannot exist

There is no `-fsys=re2`. This is a decision, not an omission.

**The thing a Zig consumer imports is `libre2bridge`, and every `re2br_*` symbol
in it is defined in `zig/bridge.cc` in this repository.** An installed upstream
`libre2.so.11` exports **none** of them — upstream has no `re2br_*` header at all,
because `addTranslateC` translates C and RE2 is C++17.

So a "system mode" that bound the installed library would have **nothing to bind
to**: the facade's dispatch would resolve against symbols the installed library
does not define, and the failure would be at link time for a linked build or at
`MissingSymbol` for a runtime-loaded one. A mode named "use the system RE2" that
cannot link the system RE2 is worse than no such mode.

**What covers the case instead.** The runtime-loaded route, honestly:
`re2.load(.{ .system = "libre2bridge.so.0" })` names a provider by name, resolves
all nine symbols, and answers `MissingSymbol` when the file it found is not one.
That is the whole of what a system mode would have offered, and it fails with a
diagnosis instead of at link time.

---

## 12. What the facade deliberately leaves unwrapped

`RE2::Set`, `FilteredRE2`, `LazyRE2`, `RE2::Arg`, and the static
`FullMatch`/`PartialMatch`/`Consume`/`FindAndConsume`/`Replace`/`GlobalReplace`
templates. The reasoning per item, and what it cost, are in `README.zig.md`'s
"What this module deliberately does not wrap".

**The common thread, which is the decision worth recording.** Each of those is a
*different shape of call* — a vector result, a dispatch decision, an alternative
lifetime, a C++-typed argument, or a fixed-order convenience — and wrapping them
would have meant adding ownership models and error contracts rather than fields.
**One ownership idiom was worth more than five more entry points**, and that is
why `MatchData`, `Buffer` and `Regex` all use `deinit` and nothing else.

**Where a static template's capability was genuinely needed it was rebuilt**, not
left out: `re2br_extract` keeps upstream's composition exactly
(`re2/re2.cc:542-557` — size from `1 + MaxSubmatch(rewrite)`, match unanchored
over the whole text, hand the vector to `RE2::Rewrite`) and makes the two things
upstream leaves implicit — the anchor and the searched byte range — explicit. So
the facade offers **more** than the templates it does not wrap.

**Nothing is lost by it.** The build compiles the whole of RE2's 22 units and
installs both header trees, so a C++ consumer reaches all of it through
`#include <re2/re2.h>`.

---

## 13. Everything still PENDING-VERIFICATION, and the gate for each

**Nothing in this package has been built, tested, smoked, installed or fetched by
this role.** No build, no test, no compiler probe, no formatter, no linter and no
git command was run against these sources. Every row is PENDING and every row
names the gate the parent driver must run.

| # | What is unproven | The gate that settles it |
|---|---|---|
| 1 | `build.zig` compiles at all, on any target | `zig build` on `x86_64-linux-gnu` |
| 2 | The 22 RE2 units and 150 Abseil units compile as one closure | the same `zig build`; the `cross-test` matrix then proves it per target |
| 3 | `zig/bridge.cc` compiles and links against the translated `zig/bridge.h` | the same |
| 4 | The `-fexceptions` decision in `platform_flags.zig` is **required**, not merely useful — that is, that `catch` in `bridge.cc` is a hard error without it | remove the flag in a scratch tree and compile; if it still compiles, the flag is decoration and the file's claim is wrong |
| 5 | The facade's public surface covers everything `tests.zig` and `smoke.zig` call | `zig build test` and `zig build smoke` |
| 6 | All six `check` targets compile | `zig build check`, and `zig build check -Dtarget=<triple>` per target, at `verify.yml:1022-1028` |
| 7 | The shared delivery links, and `libre2cpp` resolves the closure | `zig build -Dlinkage=dynamic` on an ELF target |
| 8 | `re2.pc` describes what was actually installed | `pkg-config --cflags --libs re2` against the install prefix, which is what `verify.yml:673-698` does |
| 9 | A relocated install is a package a C consumer can use | the `verify.yml` `shared-delivery` job |
| 10 | The runtime-loaded route works, and `MissingSymbol` really is what an installed `libre2` gets | `zig build -Druntime=true` plus a program that calls `re2.load` |
| 11 | The **out-of-tree `zig fetch`** — and with it, risk §8 above | a consumer `zig fetch` of this package by path |
| 12 | `UPSTREAM.sha256` validates as 1671 records | `sha256sum -c UPSTREAM.sha256` |
| 13 | The recorded path set is still *exactly* the vendored set | `tools/check-provenance.sh` — a checksum run alone cannot see a file that was **added** |
| 14 | Both licence texts are still where the records say, and `MODULE.bazel:16` still declares the pinned Abseil | the same script |
| 15 | The consumer package builds out of tree and its hand-worked offsets all hold | `cd consumer && zig build run` |
| 16 | The `libre2cpp` licence texts are installed beside it on the shared route and **absent** on the static one | `verify.yml:241-261` checks both directions |
| 17 | The four `benchlog.*` files are actually tracked in git, not only present in the working tree | `git ls-files vendor/re2/benchlog` — **not a gate; a check of whether risk §9's force-add was run** |
| 18 | ~~The 53-platform matrix runs~~ | **settled 2026-10-05**, twice: `cross-test` exited 1 over 53 targets on the first tree — 16 pass, 22 build failures, 15 `build_only` — and 16 pass, 14 build failures, 23 `build_only` after the NetBSD fix. §15 gives every cause as first recorded and §16 the corrections |
| 19 | ~~The NetBSD flag pair in `platform_flags.netbsd_flags`~~ | **settled 2026-10-05**: `zig build -Dtarget=<target>` exits 0 for all eight NetBSD cells (`aarch64`, `aarch64_be`, `arm`, `armeb`, `mips`, `mipsel`, `x86`, `x86_64`), and `nm` over the resulting `stacktrace.o` finds no `alloca` symbol, which is the `kHaveAlloca == false` state `stacktrace.cc:69-72` gives. §16 carries the rejected alternative that this replaced |

**What is an observation and not a gate result**, recorded here so it is not
mistaken for one: both vendored trees were compared against freshly extracted
upstream release archives on 2026-10-05 and matched byte for byte. The commands
are in `UPSTREAM.md`; the result is a measurement of upstream's published bytes,
and `UPSTREAM.sha256` was not run against it.

---

## 14. Two defects found while writing the consumer, and what they were

Recorded because both were found by *using* the API rather than reading it, which
is the argument for having an out-of-tree consumer at all.

**`Regex.match` referenced a binding it no longer declared.** During the
out-parameter removal, the two lines that resolved `end` and refused an
out-of-range pair went with it, leaving `end` used but undeclared in the sizing
call. A consumer writing `regex.match(subject, .{ .end = subject.len + 1 }, …)`
would not have compiled at all. The fix restored the pair immediately after the
signature. **It was found by reading the file against the contract being
documented, not by a compiler** — no compiler was run here either.

**`extract` and `quoteMeta` returned a slice a caller could not free correctly.**
Both allocated `needed + 1` and returned `buffer[0..needed]`. A caller following
the documented contract — "the buffer is owned by the caller" — writes
`allocator.free(result)`, and `GeneralPurposeAllocator.free` computes the block
size from `bytes.len` and checks it against the alignment. Under a Debug
general-purpose allocator that is a heap-corruption report on the first `extract`
anyone writes. `c_allocator` and `page_allocator` are length-insensitive and would
have hidden it, which is exactly why a casual run would not have caught it.

The fix is `Buffer`: `bytes` is exactly the content and `allocation` is exactly
what `deinit` frees, and the two have different lengths because the bridge
terminates its C string one byte past the answer it reported. `MatchData` already
allocated and freed the same length and was correct, so the facade now has **one**
ownership idiom rather than two.

**The lesson, which is the reason this section exists.** Both defects were in the
*ownership* contract, and both would have been invisible to a test that only checks
answers — every offset in `consumer/src/main.zig` was right and the package was
still wrong. `deinit`-based ownership and a `Buffer` that separates content from
allocation are not tidiness; they are what makes "free it with the allocator you
passed" a statement a caller can actually implement.

---

## 15. The 53-platform matrix, and the three target families it cannot build

**Observed 2026-10-05.** `cross-test`, run from this package root, sourcing
`cross-test.profile.sh` unmodified, with `--jobs 8 --build-jobs 8`: the harness
exited **1** after attempting all 53 targets. **16 pass, 22 build failures, 15
`build_only`, 0 partial, 0 refused**, in 8881 s. `run_id`
`20261005-191620-27278-29909`; receipt
`/home/tmp2/gertullj/scratch/foundation-libs/cross/re2` (`cross-test-summary.json`
schema 2, one `build-<target>.log` per cell).

**The sixteen that ran all ran the same eight tests.** Each passing cell's log
ends `10/10 steps succeeded; 8/8 tests passed`, on `x86_64-linux` natively and
under `qemu_user` on the other fifteen: `aarch64-linux`, `aarch64_be-linux`,
`arm-linux`, `armeb-linux`, `loongarch64-linux`, `mips-linux`, `mipsel-linux`,
`mips64-linux`, `mips64el-linux`, `riscv32-linux`, `riscv64-linux`, `s390x-linux`,
`thumb-linux`, `thumbeb-linux`, `x86-linux`. **The fifteen `build_only` cells
compiled the entire closure — 152 Abseil plus 22 RE2 units, the bridge and the
translated headers — and then had no runner**, so they are compile evidence and
not one of them is a test pass.

**Nothing refused, and that is a property of the configuration.** The one
refusal in this graph is `build.zig:1660`, a `std.debug.panic` inside
`rejectUnsupportedDynamicLinkage`, and `build.zig:1654` returns early for every
cell where `linkage != .dynamic`. `cross-test.profile.sh` sets no `-Dlinkage`, so
no cell of this matrix reached it.

**Two of the four failing families are boundaries §7 and README §3 already name**
 — Darwin and MacCatalyst, four cells, on the missing Apple SDK, and
`wasm32-wasi`, on `_LIBCPP_HAS_THREADS 0`, `_LIBCPP_HAS_FILESYSTEM 0` and the
`poison.cc` defect. The matrix adds nothing to those, and one observation belongs
with them: the harness printed `error: BrokenPipe` and no diagnostic for
`aarch64-macos`, and re-running that single cell alone at `-j1` in a fresh cache
printed the `unable to find framework 'CoreFoundation'` message. That is one
failure whose stderr was lost under `-j8`, not a second and different one.

The three below are new. **Two of them were reclassified by §16, which is the
section to read for the NetBSD and PowerPC families: the NetBSD family was this
package's to fix and is fixed, and three PowerPC statements below are withdrawn
with their refutations kept.** What follows is the record as it stood for that
run.

**NetBSD — eight cells: `aarch64`, `aarch64_be`, `arm`, `armeb`, `mips`,
`mipsel`, `x86`, `x86_64`. Two independent faults, both Abseil against this
compiler's NetBSD headers.**

* *Condition:* the vendored Abseil compiled for any `*-netbsd` target.
  *Symptom:* `absl/debugging/stacktrace.cc:64:14: error: static declaration of
  'alloca' follows non-static declaration`, with the note
  `libc/include/generic-netbsd/stdlib.h:273:7: previous declaration is here`,
  declaring `void *alloca(size_t);`. Abseil reaches for `<alloca.h>` at
  `stacktrace.cc:59-64` and, when `__has_include` is false, defines a **static**
  `alloca` of its own; NetBSD has no `alloca.h` and declares `alloca` in
  `stdlib.h` instead, so the two collide. *Fix as recorded then:* an upstream
  change — declare the fallback `extern "C"`, or branch on `__NetBSD__` the way
  the file already branches for `_WIN32`. **§16 corrects the remedy rather than
  the diagnosis**: the diagnosis is right, and `-Dalloca=__builtin_alloca` on
  the compile line fixes it without touching `vendor/`.
* *Condition:* the same cells, once that is past. *Symptom:*
  `libcxx/include/__locale_dir/support/bsd_like.h:51:38: error: no type named
  'locale_t' in the global namespace`, and everything downstream of that typedef
  failing with it — `:71:82` and `:75:83` on `__locale_t`, `:72:12` and
  `:76:12` on `strtof_l` and `strtod_l`. `bsd_like.h:51` is
  `using __locale_t _LIBCPP_NODEBUG = ::locale_t;`, and this compiler's
  `libc/include/generic-netbsd/locale.h:80-85` and `:92-96` declare `locale_t`
  **only** under `_POSIX_C_SOURCE >= 200809L`, `_NETBSD_SOURCE` or
  `__SETLOCALE_SOURCE__`. `-std=c++17` defines `__STRICT_ANSI__` and none of
  those three. **WITHDRAWN by §16, and the real cause is one line of vendored
  CCTZ**: `time_zone_format.cc:22-23` defines `_XOPEN_SOURCE 500` before its
  first `#include`, which suppresses the `_NETBSD_SOURCE` default at
  `featuretest.h:68-71`. `-std=gnu++17` produces the same twenty diagnostics,
  and `-D_NETBSD_SOURCE` produces none. *Fix:* `-D_NETBSD_SOURCE`, carried in
  `platform_flags.netbsd_flags`. *Targets bound:* every NetBSD cell.

**PowerPC — eight cells: `powerpc-linux`, `powerpc-netbsd`, `powerpc-openbsd`,
`powerpc64-linux`, `powerpc64le-linux`, `powerpc64-openbsd`,
`powerpc64-freebsd`, `powerpc64le-freebsd`. Two Abseil gaps, both independent of
the NetBSD pair above.**

* *Condition:* any PowerPC cell. *Symptom:*
  `absl/base/internal/unscaledcycleclock.cc:102:2: error: Must implement
  UnscaledCycleClock::Frequency()`. The `#error` at `:102` is the `#else` of a
  chain whose arms are `__GLIBC__` (`:86-87`), `_AIX` (`:88-91`) and
  `__FreeBSD__` (`:92-100`). A glibc PowerPC target *should* take the first arm,
  and does not: `__GLIBC__` is a `<features.h>` macro, and this translation unit
  includes only `absl/base/internal/unscaledcycleclock.h` at `:15` — nothing that
  would have pulled `features.h` in before `:86`. The FreeBSD cells take their
  own arm and never reach the `#error`, which is why `powerpc64-freebsd` reports
  one error and `powerpc64-linux` reports two. *Fix:* upstream — include
  `<features.h>`, or select on `__linux__` as `Now()` at `:64-82` already can.
  *Targets bound:* every PowerPC cell except the two FreeBSD ones, which fail on
  the next cause alone.
  **WITHDRAWN by §16:** the cells that fail are musl, OpenBSD and NetBSD, and
  none of those libcs defines `__GLIBC__` at all. Measured on this pin,
  `powerpc64le-linux-gnu` compiles this unit clean, so a glibc PowerPC target
  does take the first arm and `<features.h>` is not the missing piece.
* *Condition:* the same cells. *Symptom:*
  `absl/random/internal/nanobenchmark.cc:55:10: error: 'sys/platform/ppc.h' file
  `nanobenchmark.cc:53-56` includes that FreeBSD-only header under
  `#if defined(ABSL_ARCH_PPC)`, so it is required on every PowerPC target
  including the Linux and OpenBSD ones, where the file does not exist. *Fix:*
  upstream, by narrowing the guard to `__FreeBSD__`. *Targets bound:* every
  PowerPC cell.
  **WITHDRAWN by §16:** `sys/platform/ppc.h` is a **glibc** header, not a
  FreeBSD one — `libc/include/generic-glibc/sys/platform/ppc.h:28` declares
  `__ppc_get_timebase(void)` and `libc/include/generic-glibc/bits/ppc.h:29`
  declares `__ppc_get_timebase_freq(void)`, the name `nanobenchmark.cc:729`
  calls. FreeBSD does not ship it either, which is why the two FreeBSD cells
  fail here. The upstream fix is a `__GLIBC__` guard, not a `__FreeBSD__` one.
* *Condition:* the 32-bit `powerpc-linux` cell only. *Symptom:*
  `absl/debugging/internal/examine_stack.cc:181:57: error: no member named
  'uc_regs' in 'mcontext_t'`, and the same read at
  `stacktrace_powerpc-inl.inc:139`. The `__powerpc__` arm
  of `examine_stack.cc:180-181` uses `uc_mcontext.uc_regs->gregs`, which is
  glibc's layout on some BSDs and not glibc's on Linux. *Fix:* upstream, one more
  arch arm. *Targets bound:* `powerpc-linux`; the 64-bit Linux cell fails on the
  two causes above and does not reach this one.
  **Corrected by §16:** it is the BSD `mcontext_t` layout Abseil spells, and
  this toolchain's musl header puts `uc_regs` on the *ucontext*
  (`libc/include/powerpc-linux-musl/bits/signal.h:67`) while `mcontext_t`
  (`:33-42`) has `gregset_t gregs`, so `uc_mcontext.uc_regs` names a member that
  exists on neither.

**Hexagon — one cell: `hexagon-linux`.** *Condition:* the vendored Abseil
compiled for a 32-bit RISC target it does not list. *Symptom:* three errors at
once — `absl/base/internal/direct_mmap.h:130:17: error: static assertion failed
due to requirement 'sizeof(unsigned long) == 8': Platform is not 64-bit` (the
static assertion guards the 64-bit arm of `DirectMmap`, and Zig's Hexagon is
32-bit); `absl/debugging/internal/examine_stack.cc:202:2: error: "Undefined
Architecture."` (the `#error` of a chain with no Hexagon arm); and
`absl/log/internal/conditions.h:239:42: error: use of undeclared identifier
'_exit'`. *Fix:* upstream, in each of the three files. *Targets bound:*
`hexagon-linux` only — the same closure compiles for every other 32-bit cell in
the table (`arm-linux`, `thumb-linux`, `x86-linux`, `mips-linux` and the rest all
pass or run), so this is a Hexagon gap and not a word-size policy.

**What is bound to this toolchain.** Every cause above is either a line in
`vendor/abseil-cpp`, which this package does not edit and must keep byte for
byte, or a header this compiler ships. All four families were read as upstream
or toolchain boundaries, and **none of them is a silent skip**: every cell was
attempted, every one is in the summary with its log, and no test, flag or target
was removed to make the run tidier. **§16 corrects one of the four readings:**
the NetBSD family was not a boundary but this package's own compile line, and
all eight of its cells build now. The other three stand as boundaries.

### What a second run of this matrix has to do first, and why this one cannot prove it did

This run observed 53 cells between 19:16 and 21:44. Two fork-owned files have
later mtimes — `build_support/platform_flags.zig` at 21:58:56 and `build.zig` at
21:59:24 — both from another role's WASI work, both after the last cell
finished. That is why the `wasm32-wasi` cell above is not reported as a result
for the tree as it now stands.

**The lesson, and the limit of what this run can claim.** *Condition:* a
multi-hour matrix run in a tree that other roles are editing at the same time.
*Symptom:* a run whose cells may have been produced from two different source
states, which is not a result at all — it cannot be re-read, re-interpreted or
partially rescued, and the failure is invisible because every cell still has a
log. *Fix:* hash the fork-owned sources — `build.zig`, `build_support/*.zig`,
`zig/**`, `tests.zig`, `smoke.zig` — before the run and again after it, and
discard the run if the two manifests differ; do not re-run and hope the second
one is coherent. *Targets bound:* every gate in this package, and the same
hazard applies to `check`, `test` and `smoke` whenever they run for minutes.

**And the weaker half of that fix, stated so the next role does not rely on it.**
An mtime is a last-write stamp, not a history: a file written at 20:00 and again
at 21:59 looks exactly like a file last written at 21:59. So **an mtime check
cannot establish that the 53 cells above came from one source state.** What this
run actually has is three weaker things — no fork-owned file's current mtime
falls inside the run window; the `wasm32-wasi` log still carries the pre-edit
`signal.h` error, which is positive evidence for that one file; and no cell's
diagnostics are mutually inconsistent. A stability window on its own is not
enough either: a file can sit unchanged while a concurrent rename leaves it
half-merged and not compiling, so the check that counts is **the changed file
compiling with the flags `build.zig` actually passes**, not its timestamp.

**Nothing about the storage rules was bent for this run**, and the rule is worth
restating where a later role will read it: every byte of this receipt — logs,
`cross-test-summary.json`, the probes, the harness's own per-run cache — is under
`$HOST_SCRATCH_ROOT`, and nothing was written to `/tmp`, `/var/tmp`, `$HOME` or
the repository. The repository received three documentation files and no build
output, no cache and no source change.

---

## 16. The NetBSD family was this package's, and the PowerPC record above is wrong in three places

§15 classified four failing families as upstream or toolchain boundaries. That
was right for PowerPC, Hexagon and Darwin, and **wrong for NetBSD**: two of the
eight NetBSD cells' causes are build configuration, this package owns the
compile line, and both are now fixed. This section carries the corrections with
the measurements that establish them, because two of the recorded *causes* are
refuted and a later role must not inherit them.

### The `locale_t` cause in §15 is WITHDRAWN, and the real one is one line of vendored CCTZ

§15 and `CHANGELOG.md` entry 10 both say the failure is that `-std=c++17`
defines `__STRICT_ANSI__` and none of `_POSIX_C_SOURCE >= 200809L`,
`_NETBSD_SOURCE` or `__SETLOCALE_SOURCE__`. The header facts in that sentence
are right; the cause is not. **The C++ standard is not the lever, and it is
measured, not argued.** Compiling the one failing unit
(`vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc`) for
`x86_64-netbsd` on this pin:

| flags | diagnostics |
|---|---|
| `-std=c++17 -fexceptions -DNOMINMAX` | 20 |
| `-std=gnu++17 -fexceptions -DNOMINMAX` | 20 |
| `-std=c++17 -fexceptions -DNOMINMAX -D_NETBSD_SOURCE` | 0 |

What actually happens is this. `time_zone_format.cc:22-23` defines
`_XOPEN_SOURCE 500` **before its first `#include` at `:28`**, so
`libc/include/generic-netbsd/sys/featuretest.h:68-71` — "if none of the major
macros is defined, `_NETBSD_SOURCE` is assumed" — never applies its default,
because CCTZ has just defined one. `_XOPEN_SOURCE 500` then implies
`_POSIX_C_SOURCE 199506L` (`featuretest.h:131`), which is below the 200809L that
`libc/include/generic-netbsd/locale.h:80-86` and `:92-97` require before they
declare `locale_t`, `newlocale` and the `*_l` family. libc++ needs `::locale_t`
at `libcxx/include/__locale_dir/support/bsd_like.h:51`, reached from that same
unit through `time_zone_format.cc:28` -> `cctz/time_zone.h:23` ->
`libcxx/include/chrono:1114` -> `forward_list:1633` -> `functional:601` ->
`vector:363` -> `locale:197` -> `__locale:17` ->
`__locale_dir/locale_base_api.h:120` -> `support/netbsd.h:20` -> `bsd_like.h`.
Without CCTZ's line the default `_NETBSD_SOURCE` would apply and the whole
chain would compile — which is why this compiles fine on every other libc in the
table and on `x86_64-netbsd` in a translation unit that includes `<locale.h>`
first.

*Fix, and it is build configuration.* `-D_NETBSD_SOURCE`, carried by
`build_support/platform_flags.zig`'s `netbsd_flags` for `os.tag == .netbsd` and
applied to **both** C++ closures, because `vendor/re2/re2/re2.h:221-222` makes
them one header closure and a list that differed between them would be two
answers to the same question about the same header. It restores the feature set
these sources get on a NetBSD build that does not pre-define
`_XOPEN_SOURCE`, and the two together are the documented union case rather than
a conflict: `featuretest.h:44-50` says that when more than one major
feature-test macro is defined the sets are unioned. `_DEFAULT_SOURCE` is not an
alternative — it is FreeBSD's macro name and `featuretest.h` has no arm for it.
*Targets bound:* every `*-netbsd` cell, and nothing else; the predicate is one
`os.tag` test, so a target with another libc never sees the macro.

### The `alloca` collision in §15 is reclassified, and the first fix tried for it was wrong

§15 recorded this one as upstream-only ("declare the fallback `extern "C"`, or
branch on `__NetBSD__` the way the file already branches for `_WIN32`"). That is
true about the vendored source and it is not the only lever. The upstream shape
is unchanged and still upstream's:
`vendor/abseil-cpp/absl/debugging/stacktrace.cc:57-64` reads
`#if __has_include(<alloca.h>)`, and its `#elif !defined(alloca)` at `:63-64`
declares a **static** `alloca`. NetBSD ships no `alloca.h`
(`libc/include/generic-musl/alloca.h`, `generic-glibc/alloca.h` and
`any-darwin-any/alloca.h` exist; no NetBSD one does) and declares `alloca` as a
function, `void *alloca(size_t);`, at
`libc/include/generic-netbsd/stdlib.h:273`, so `!defined(alloca)` is true and the
two declarations collide. The neighbouring libcs are the reason this is
NetBSD-only and not a BSD-wide fault: musl
(`libc/include/generic-musl/alloca.h:13`), FreeBSD
(`libc/include/generic-freebsd/stdlib.h:258`) and OpenBSD
(`libc/include/generic-openbsd/stdlib.h:267`) all
`#define alloca __builtin_alloca`.

*The fix that landed.* `-Dalloca=__builtin_alloca` in
`platform_flags.netbsd_flags` — the same idiom the three libcs above already
use, applied to the one that does not. It makes both of Abseil's arms false at
once: `__has_include(<alloca.h>)` stays false because NetBSD still has no such
header, and `!defined(alloca)` becomes false, so no static fallback is declared
and the collision has nothing to collide with.

*What that preserves, and why it is the point.* `ABSL_INTERNAL_HAVE_ALLOCA`
stays undefined, so `kHaveAlloca` (`stacktrace.cc:69-72`) stays false and the
`if constexpr (kHaveAlloca)` blocks at `stacktrace.cc:158` and `:178` are never
instantiated. That is exactly the state upstream's own static-fallback arm would
have produced, because that arm at `:63-64` defines no macro either: Abseil's
NetBSD stack unwinder keeps the no-alloca path the file was written to take.
Measured on the objects this tree now produces: `nm` over every `stacktrace.o`
in the NetBSD build cache reports **no** `alloca` symbol, while every object
built during the rejected attempt below reports `U alloca`.

*The rejected alternative is recorded because it compiled, built four cells, and
was still wrong.* Answering the `__has_include` probe from the include path — a
generated `alloca.h` that includes `<stdlib.h>`, the mechanism
`windowsIntrinsPreludeDir` already uses — also clears both diagnostics. It takes
Abseil's **first** arm: `ABSL_INTERNAL_HAVE_ALLOCA 1`, `kHaveAlloca` true, and
the four `alloca` calls at `stacktrace.cc:161,162,181,182` that upstream's
NetBSD path never makes. Four of the eight NetBSD cells then compiled and
linked; the other four failed at link with `ld.lld: undefined symbol: alloca`,
referenced from those lines inside `libabsl.a` (`arm`, `armeb`, `x86`, `x86_64`
linked; `aarch64`, `aarch64_be`, `mips`, `mipsel` did not). A fix that buys four
cells by turning on a path Abseil deliberately leaves off, and loses the other
four, is not a fix; the generated header and its `build.zig` wiring are gone
from the tree.

### PowerPC: the §15 record is wrong about the header and about the `#error`

Both of §15's PowerPC causes survive as *failures*; neither survives as a
*statement*.

* **`sys/platform/ppc.h` is a glibc header, not a FreeBSD one.** §15 calls it
  "that FreeBSD-only header" and proposes narrowing the guard to
  `__FreeBSD__`. It is glibc's PowerPC platform header:
  `libc/include/generic-glibc/sys/platform/ppc.h:28` declares
  `__ppc_get_timebase(void)` and `libc/include/generic-glibc/bits/ppc.h:29`
  declares `__ppc_get_timebase_freq(void)` — the two names
  `vendor/abseil-cpp/absl/random/internal/nanobenchmark.cc:729` calls.
  FreeBSD does not ship it either, which is why the two FreeBSD cells
  (`powerpc64-freebsd`, `powerpc64le-freebsd`) fail on this cause alone. The
  upstream fix is to guard the include on `__GLIBC__`, or on the header's
  existence, not on `__FreeBSD__`.
* **The `#error` at `unscaledcycleclock.cc:102` is not a missing
  `<features.h>`.** §15 says a glibc PowerPC target "should take the first arm,
  and does not", because `__GLIBC__` is a `<features.h>` macro that this
  translation unit never pulls in. Measured on this pin, with this compiler and
  these flags, compiling the four units that carry the PowerPC arms —
  `unscaledcycleclock.cc`, `nanobenchmark.cc`, `stacktrace.cc`,
  `examine_stack.cc`:

  | target | result |
  |---|---|
  | `powerpc64le-linux-gnu` | clean |
  | `powerpc64le-linux` (musl) | `#error` at `:102`, `sys/platform/ppc.h` not found |
  | `powerpc64-freebsd` | `sys/platform/ppc.h` not found |
  | `powerpc-openbsd` | `#error` at `:102`, `sys/platform/ppc.h` not found |

  A glibc PowerPC target does take the first arm. The cells that fail are musl
  and OpenBSD and NetBSD, and none of those libcs defines `__GLIBC__`, `_AIX` or
  `__FreeBSD__` — the three arms at `unscaledcycleclock.cc:86-100`. The macro is
  a libc header macro rather than a compiler one, and its reachability is
  measured rather than assumed: a probe unit that includes
  `absl/base/config.h` compiles clean on `powerpc64le-linux-gnu` with
  `__GLIBC__` defined, and fails on `powerpc64le-linux` with "__GLIBC__ NOT SEEN
  after absl/base/config.h". That is also the direct refutation of §15's "nothing
  that would have pulled `features.h` in before `:86`": on a glibc target
  something does pull it in, through
  `vendor/abseil-cpp/absl/base/config.h:52` and the headers behind it.
* **The 32-bit item is a musl/BSD layout mismatch, and the recorded wording is
  garbled.** `absl/debugging/internal/examine_stack.cc:180-181`'s
  `__powerpc__` arm reads `context->uc_mcontext.uc_regs->gregs[32]`, and
  `stacktrace_powerpc-inl.inc:136-140` does the same. This toolchain's musl
  header puts `uc_regs` on the *ucontext*
  (`libc/include/powerpc-linux-musl/bits/signal.h:67`, `mcontext_t *uc_regs;`)
  and gives `mcontext_t` (`:33-42`) a `gregset_t gregs` instead, so
  `uc_mcontext.uc_regs` names a member that exists on neither.

*Two levers were considered and both are rejected on measurement.*

1. **`-DABSL_USE_UNSCALED_CYCLECLOCK=0`.** Upstream sanctions exactly this
   spelling at `vendor/abseil-cpp/absl/base/internal/unscaledcycleclock_config.h:46-51`
   ("Can be overridden at compile-time via
   `-DABSL_USE_UNSCALED_CYCLECLOCK=0|1`"), and Abseil itself defaults it to 0 on
   platforms that often lose access to the hardware counter. It removes the
   `#error`, because the whole body of `unscaledcycleclock.cc` is under
   `#if ABSL_USE_UNSCALED_CYCLECLOCK` at `:17`. It also fixes **none** of the
   eight cells: `nanobenchmark.cc:53-55` fails on all eight, so the flag buys a
   diagnostic-free compile of one unit out of 152 and changes Abseil's timing
   source on targets where upstream has no timing implementation to preserve.
2. **A `sys/platform/ppc.h` prelude**, the same trick as NetBSD's `alloca.h`.
   It would have to declare `__ppc_get_timebase_freq()`, and the only libc in
   this toolchain that declares it is glibc, at
   `libc/include/generic-glibc/bits/ppc.h:29`. Supplying it would mean writing a
   new platform primitive into a header that pretends to be someone else's,
   which is the substitution this workspace forbids.

*Conclusion:* the PowerPC family is an upstream Abseil gap — one that needs a
`__GLIBC__` guard it does not have in `nanobenchmark.cc:53-55` and one that needs
a musl/BSD implementation it does not have in `unscaledcycleclock.cc:86-100` —
on eight targets whose libc this package does not ship. It stays eight build
failures. No cell is skipped and no unit is dropped from
`build_support/absl_sources.zig` to make it tidier.

### Hexagon and Darwin: confirmed, and the measurements that bound them

Both §15 records hold as written. `hexagon-linux` fails on three upstream arms
at once — `absl/base/internal/direct_mmap.h:130` static-asserts a 64-bit
`unsigned long` in the `#else` of its architecture chain, on a 32-bit target;
`absl/debugging/internal/examine_stack.cc:202` is the `#error` of a chain with
no Hexagon arm; `absl/log/internal/conditions.h:239` calls `_exit` with no
declaration reachable. The same closure compiles for every other 32-bit cell in
the table, which is what makes it a Hexagon gap and not a word-size policy.
Din fail on `vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_lookup.cc:22-23`,
which includes `<CoreFoundation/CFTimeZone.h>` under `#if defined(__APPLE__)`;
this host has no Apple SDK, and the compiler's own
`libc/include/any-darwin-any/` holds headers and no `.framework` directories, so
the driver reports "unable to find framework 'CoreFoundation'. searched paths:
none". Re-running `aarch64-macos` alone at `-j1` in a fresh cache prints that
message where the 8-job matrix printed `error: BrokenPipe` and nothing else, so
that is one failure whose stderr was lost under load, not a second one.

### What this run did about its own source state

§15's closing note is the rule; this is the receipt for following it. The 23
fork-owned files that decide what gets compiled — `build.zig`, `build.zig.zon`,
the four `build_support/*.zig`, the five `zig/**`, the five `runtime/**`, the two
`consumer/**`, `tests.zig`, `smoke.zig`, `cross-test.profile.sh` and
`tools/check-provenance.sh`, with `vendor/**` deliberately excluded because
`tools/check-provenance.sh` is the gate for those bytes — were hashed before
the run into `fork-sources.pre.sha256` and again after it into
`fork-sources.post.sha256`, under
`$HOST_SCRATCH_ROOT/scratch/foundation-libs/cross/re2b`, and the two manifests
are compared rather than eyeballed. Two further rules from the same lesson were
applied: a stability window is necessary but not sufficient, so the changed
files were also **compiled with the flags `build.zig` actually passes** before
the run started (`zig build test -Dtarget=x86_64-netbsd` compiles the whole
closure and then reports the run step unable to execute a foreign binary, which
is the expected shape), and no byte of this work went to `/tmp`, `/var/tmp`,
`$HOME` or the repository.