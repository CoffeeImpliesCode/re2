/* SPDX-License-Identifier: BSD-3-Clause
 *
 * The one header `zig build` translates, and the aggregate it exists to hold.
 *
 * What it is
 * ----------
 * `build.zig`'s `addGraph` points `b.addTranslateC` at this file, and what that
 * step produces is the `c` module `zig/root.zig` imports -- or, under
 * `-Druntime=true`, the input `runtime/generate.zig` reads and turns into the
 * generated dispatch that replaces it (`runtime/graph.zig`'s `createModule`).
 * One translation, one module, either way: this file is the root of it, so
 * every declaration the facade can reach is reachable from exactly one place
 * and a second header could not silently produce a second description of the
 * same surface.
 *
 * It aggregates one header, and that is the whole of its content:
 *
 *   bridge.h   this fork's C surface over upstream C++17.  Nine `re2br_*`
 *              entry points, the `Re2Bridge*` types they take and return, and
 *              the `RE2BRIDGE_*` constants -- included *whole*, with its own
 *              include guard, never restated.  A copy of any declaration here
 *              would be a second answer to "what does the C boundary say", and
 *              the two could disagree without any build failing: the compiled
 *              side is `zig/bridge.cc` including this same `bridge.h`, so a
 *              restatement here is a description of a header the code does not
 *              compile.
 *
 * Nothing upstream is included, and that is a decision rather than an
 * oversight.  `addTranslateC` translates C; RE2 at this pin is C++17 with a
 * class, a `std::string` and `absl::string_view`, and `vendor/re2/re2/re2.h`
 * declares none of what the bridge needs in a way a C translator could read.
 * `zig/bridge.h:12-19` states the same fact from the other direction, and it is
 * why the compiled side is `zig/bridge.cc` rather than an upstream header
 * handed to the translator.
 *
 * Upstream's own headers therefore never appear on this translation line, and
 * the include roots that reach them are deliberately **not** on it either.
 * `runtime/graph.zig:31-52` records that decision from the other side and
 * `build.zig`'s `addGraph` implements it: `zig/bridge.h:81-82` includes only
 * `<stddef.h>` and `<stdint.h>` and names no upstream type, so `vendor/re2`
 * and `vendor/abseil-cpp` on the translation line would be `-I` roots that
 * resolve nothing.  The translation is a description of *this* bridge header
 * and of nothing else; the compiled side is the opposite, needing all three
 * roots, which is why a consumer that breaks against a changed upstream header
 * breaks in `zig/bridge.cc` rather than here.
 *
 * That is why the only root `addGraph` puts on this step is `zig/` itself, for
 * the `#include` below: an include that is needed is on the line, and an
 * include root that would resolve nothing is not a licence to add a header
 * above.  If a future `zig/bridge.h` *did* name an upstream type, that would be
 * a change to `build.zig`'s `addGraph` with a name in it, and the comment there
 * records what has to move.
 *
 * Why the aggregator exists at all, when `zig/bridge.h` is already a header
 * ----------------------------------------------------------------------
 * Because the *installed* surface and the *translated* surface are two
 * different questions with two different answers, and the installed one already
 * has its own name.  `zig build` installs `zig/bridge.h` as
 * `include/re2_bridge.h`, under the name a C consumer of the installed tree
 * includes -- and `.github/workflows/verify.yml` compiles two programs against
 * exactly that name.  Giving the translation root the same file as the
 * installed header would make one path carry two roles, so that installing it
 * under a second name and translating it under its own would have to be
 * re-derived at every call site.  Splitting them keeps the installed name a
 * property of the install (`addBridge`) and the translated name a property of
 * the translation (`addGraph`), and this file is where the aggregate they share
 * is named.
 *
 * What must not change here
 * -------------------------
 * No `#define` of this build's own, and no macro that describes the *platform*.
 * The standard, the exception setting and the `windows.h` policy live on the
 * compile line in `build_support/platform_flags.zig`, and they are given to the
 * bridge's own compilation and to nothing here: a declaration in this
 * translation is a description of an interface, not a statement about which
 * target it was read for.  A `-D` here would make the translated types depend
 * on a switch a C consumer of `re2_bridge.h` does not have.
 *
 * The one thing this file must never become is a second copy of the surface.
 * If a declaration is added, it is added to `zig/bridge.h` and arrives here by
 * that include; nothing is written below the line.
 */

#include "bridge.h"