/* SPDX-License-Identifier: BSD-3-Clause
 *
 * The RE2 bridge: a real `extern "C"` surface over the upstream C++ engine.
 *
 * Every declaration here is a thin, named wrapper around one upstream call on
 * one real RE2 type.  Nothing in this file matches a pattern, rewrites a match
 * or escapes a metacharacter: `RE2::Compile`, `RE2::Match`, `RE2::Rewrite`,
 * `RE2::QuoteMeta` and `RE2::CheckRewriteString`, and every other answer this
 * package publishes, come from the compiled upstream C++17 in
 * `vendor/re2/re2` and `vendor/re2/util`, reached through `zig/bridge.cc`.
 *
 * Why a bridge at all: the upstream library
 * is C++17 with a class, `std::string`, `absl::string_view` and name-mangled
 * linkage.  `addTranslateC` translates C headers, not C++ headers, so the C
 * surface a Zig caller needs is written once, here, as a header the translator
 * can read and a translation unit the compiler can compile.  This header is
 * therefore plain C99 with `extern "C"` guards: it must stay parseable by a C
 * translator, not only by a C++ compiler.
 *
 * Two consequences of that rule are load-bearing and are stated here so a later
 * edit does not undo them by accident:
 *
 *   * It includes `<stddef.h>` and `<stdint.h>` and nothing else.  Every
 *     declaration is then a `re2br_*` function or a `RE2BRIDGE_*` constant,
 *     and the runtime loader's extern sweep has no C library declaration to
 *     mistake for one of ours.  A bridge header that reaches `<string.h>`,
 *     `<stdlib.h>` or `<math.h>` has to grow `runtime/graph.zig`'s
 *     `libc_noise` list at the same time, and that list is a measured file.
 *   * It names no upstream type.  `RE2::Options` reaches the caller as
 *     `Re2BridgeOptions` and `absl::string_view` never appears, so the
 *     translated Zig module is a description of *this* surface and not of an
 *     upstream one that could change under it.
 *
 * Conventions
 * -----------
 *  * Status.  Every entry point returns `Re2BridgeStatus`.  `RE2BRIDGE_OK` is
 *    zero, and no other value means the call did its work.  `RE2BRIDGE_NO_MATCH`
 *    is not a failure and not a success either: it is the one status that means
 *    "the engine ran correctly and declined to match", which is a fact the
 *    caller has to be able to distinguish from a rejected argument.
 *  * Validation.  Arguments are checked here, before the upstream call, with
 *    ordinary comparisons, and a rejected argument is
 *    `RE2BRIDGE_INVALID_ARGUMENT`.  Nothing is `assert`ed: an `assert` is
 *    removed in fast optimization mode, so a bound check that vanishes is a bound check
 *    that lies.  This is not decoration -- see `re2br_match` below, where
 *    upstream itself folds a bad offset pair into "no match" and a caller that
 *    only forwarded the call could never tell the two apart.
 *  * The unit of every offset is the BYTE.  RE2's subject is an
 *    `absl::string_view` (`re2/re2.h:585`) and `RE2::Match` documents its
 *    bounds as offsets into it (`re2/re2.h:565-566`, "Match against text
 *    starting at offset startpos and stopping the search at offset endpos").
 *    There is no second unit at this pin: RE2 has no UTF-16 or UTF-32 subject
 *    form.  Under `RE2BRIDGE_ENCODING_LATIN1` one byte is also one code point,
 *    so a byte offset is a code-point offset; under the UTF-8 default it is
 *    not, and the facade says so rather than pretending otherwise.
 *  * Buffers.  Every output buffer belongs to the caller and is borrowed for
 *    the duration of the call.  Every span- and string-returning entry point
 *    is two-pass: pass `NULL` -- or a buffer with `cap == 0` -- to learn the
 *    required length in `*out_len`, write nothing, and get `RE2BRIDGE_OK`.
 *    That is the sizing call, and it is the only one that succeeds without
 *    room: a positive `cap` too short for the result is
 *    `RE2BRIDGE_BUFFER_TOO_SMALL`, with the required length still in
 *    `*out_len` and the buffer itself untouched.
 *  * Owned objects.  `Re2BridgeRegex` is an opaque handle whose storage is
 *    allocated and freed by C++ here, never by a caller and never by Zig.
 *    `re2br_regex_destroy` is the matching free; the Zig facade's `deinit`
 *    calls exactly that.  It is idempotent on NULL and a no-op otherwise.
 *  * Allocation.  A scalar call allocates nothing beyond what the upstream
 *    function itself must allocate; `re2br_quote_meta` returns upstream's own
 *    `std::string`, and `re2br_extract` builds into upstream's own
 *    `std::string` through `RE2::Rewrite` and copies out of it once.
 *
 * Line references are to files under `vendor/re2` of this repository at the
 * pinned upstream tag, and name the file each time so a reader never has to
 * guess.
 */

#ifndef RE2_BRIDGE_H_
#define RE2_BRIDGE_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Result of every entry point. */
typedef enum Re2BridgeStatus {
  /* The call did its work. */
  RE2BRIDGE_OK = 0,
  /* An argument was out of range, NULL, or an option value upstream does not
   * accept.  No usable result was produced. */
  RE2BRIDGE_INVALID_ARGUMENT = 1,
  /* The pattern did not compile.  `re2br_regex_error` reports why, borrowed
   * from the RE2 object, for as long as that object lives. */
  RE2BRIDGE_BAD_PATTERN = 2,
  /* A caller-owned output buffer was too small.  `*out_span_count` or
   * `*out_len`, where the entry point has one, holds the required length. */
  RE2BRIDGE_BUFFER_TOO_SMALL = 3,
  /* An upstream C++ allocation failed. */
  RE2BRIDGE_OUT_OF_MEMORY = 4,
  /* The rewrite template is malformed or asks for a group the pattern does not
   * have.  This is the status `RE2::CheckRewriteString` exists to prevent
   * (`re2/re2.h:592-601`), surfaced rather than swallowed. */
  RE2BRIDGE_BAD_REWRITE = 5,
  /* The engine ran and declined to match.  Never returned with any span or
   * output byte written. */
  RE2BRIDGE_NO_MATCH = 6
} Re2BridgeStatus;

/* `RE2::Encoding` (`re2/re2.h:673-676`).  The engine defines exactly two
 * encodings at this pin; there is no "any byte" mode. */
#define RE2BRIDGE_ENCODING_DEFAULT 0 /* upstream's default, EncodingUTF8
                                      * (`re2/re2.h:680`) */
#define RE2BRIDGE_ENCODING_UTF8 1    /* RE2::EncodingUTF8  */
#define RE2BRIDGE_ENCODING_LATIN1 2  /* RE2::EncodingLatin1 */

/* `RE2::Anchor` (`re2/re2.h:542-546`). */
#define RE2BRIDGE_UNANCHORED 0   /* RE2::UNANCHORED   */
#define RE2BRIDGE_ANCHOR_START 1 /* RE2::ANCHOR_START */
#define RE2BRIDGE_ANCHOR_BOTH 2  /* RE2::ANCHOR_BOTH  */

/* Both fields of a span whose group did not take part in the match.
 *
 * RE2 reports such a group as a default-constructed `absl::string_view`, whose
 * `data()` is NULL (`re2/re2.h:571-572`, and again in the caveat at
 * `re2/re2.h:581-584`).  A group that matched the empty string has exactly the
 * same NULL `data()`, so upstream itself cannot tell "did not participate"
 * from "participated and was empty" once the text is empty; this bridge
 * reports NULL as "no range", which is the honest reading of the only signal
 * upstream gives.  It is `~0` rather than 0 so that a span is never confused
 * with a real match at offset 0.
 *
 * It is named `RE2BRIDGE_SPAN_NO_MATCH` and not `RE2BRIDGE_NO_MATCH` because
 * that name is already the sixth member of `Re2BridgeStatus` above, and it
 * means the other thing: "the engine ran and declined to match".  One name
 * cannot carry both, and a macro silently wins over the enumerator in every
 * C or C++ expression written after this line, so a caller writing
 * `status == RE2BRIDGE_NO_MATCH` would have been comparing a status against
 * `~0` and never once matched.  The sentinel is the span's, and says so. */
#define RE2BRIDGE_SPAN_NO_MATCH ((size_t)-1)

/* How one boolean option was chosen.
 *
 * This is a tri-state and not a plain `uint8_t` because upstream does not
 * default its booleans to false.  `Options()` sets `log_errors_(true)`
 * (`re2/re2.h:683`) and `case_sensitive_(true)` (`re2/re2.h:688`) and every
 * other boolean to false (`re2/re2.h:681-691`), so a field that meant "zero is
 * false, zero is the default" would silently turn logging off and case folding
 * on the first time anyone wrote `{0}` and meant nothing.  Naming the three
 * states makes "leave it alone" expressible, which is what a zero-initialised
 * struct has to mean.
 *
 * Any value other than these three is `RE2BRIDGE_INVALID_ARGUMENT`; it is
 * checked, not clamped and not ignored. */
typedef enum Re2BridgeFlag {
  /* Leave upstream's own default. */
  RE2BRIDGE_FLAG_DEFAULT = 0,
  /* Force the option on: `RE2::Options::set_<name>(true)`. */
  RE2BRIDGE_FLAG_ON = 1,
  /* Force the option off: `RE2::Options::set_<name>(false)`. */
  RE2BRIDGE_FLAG_OFF = 2
} Re2BridgeFlag;

/* Compile options, one field per public setter on `RE2::Options`.
 *
 * Every field is a zero-means-"whatever upstream does" value, so `{0}` -- and
 * a partial literal -- is valid and means "all of upstream's defaults".  The
 * `*_default` comment on each field is that default, copied out of
 * `Options()`'s constructor initialiser list at `re2/re2.h:678-692`, so a
 * reader can check it here rather than reading the constructor. */
typedef struct Re2BridgeOptions {
  /* `RE2::Options::max_mem` (`re2/re2.h:696-697`).  Default `kDefaultMaxMem`,
   * 8 << 20 (`re2/re2.h:671`).  Zero means that default. */
  int64_t max_mem;
  /* One of the RE2BRIDGE_ENCODING_* constants.  Default `RE2BRIDGE_ENCODING_UTF8`
   * (`re2/re2.h:680`); use RE2BRIDGE_ENCODING_DEFAULT to say so. */
  int32_t encoding;
  /* `posix_syntax` (`re2/re2.h:702-703`).  Default false (`re2/re2.h:681`). */
  uint8_t posix_syntax;
  /* `longest_match` (`re2/re2.h:705-706`).  Default false (`re2/re2.h:682`). */
  uint8_t longest_match;
  /* `log_errors` (`re2/re2.h:708-709`).  Default TRUE (`re2/re2.h:683`). */
  uint8_t log_errors;
  /* `literal` (`re2/re2.h:711-712`).  Default false (`re2/re2.h:684`). */
  uint8_t literal;
  /* `never_nl` (`re2/re2.h:714-715`).  Default false (`re2/re2.h:685`). */
  uint8_t never_nl;
  /* `dot_nl` (`re2/re2.h:717-718`).  Default false (`re2/re2.h:686`). */
  uint8_t dot_nl;
  /* `never_capture` (`re2/re2.h:720-721`).  Default false (`re2/re2.h:687`). */
  uint8_t never_capture;
  /* `case_sensitive` (`re2/re2.h:723-724`).  Default TRUE (`re2/re2.h:688`). */
  uint8_t case_sensitive;
  /* `perl_classes` (`re2/re2.h:726-727`).  Default false (`re2/re2.h:689`). */
  uint8_t perl_classes;
  /* `word_boundary` (`re2/re2.h:729-730`).  Default false (`re2/re2.h:690`). */
  uint8_t word_boundary;
  /* `one_line` (`re2/re2.h:732-733`).  Default false (`re2/re2.h:691`). */
  uint8_t one_line;
} Re2BridgeOptions;

/* One capture's extent, as a half-open byte range into the subject.
 * `start == RE2BRIDGE_SPAN_NO_MATCH` means the group did not take part. */
typedef struct Re2BridgeSpan {
  size_t start;
  size_t end;
} Re2BridgeSpan;

/* An opaque, C++-owned RE2. Declare a pointer, never the object. */
typedef struct Re2BridgeRegex Re2BridgeRegex;

/* ---------------------------------------------------------------------------
 * Compile
 * ------------------------------------------------------------------------- */

/* Writes the all-defaults option set.  Writes through `out`, so `out` is not
 * `const` here; `re2/re2.h:678-692` is where the defaults come from. */
void re2br_options_init(Re2BridgeOptions* out);

/* Compiles `pattern`, which is `pattern_len` bytes at `pattern` and need not
 * be NUL-terminated, into `*out_regex`.
 *
 * `options` may be NULL, meaning every upstream default.  `pattern` may be
 * NULL only when `pattern_len` is 0, which upstream accepts as the empty
 * pattern; an empty pattern is a real pattern and compiles.
 *
 * `*out_regex` is cleared before anything can fail, so a caller that ignores
 * the status holds NULL rather than an indeterminate pointer.
 *
 * `RE2BRIDGE_BAD_PATTERN` is the one status that still hands back a live
 * handle, and that is upstream's own model rather than a convenience here: a
 * rejected pattern leaves a `RE2` whose `ok()` is false and whose `error()`
 * is populated, and `error()` reads off that object
 * (`re2/re2.h:313-316`), so destroying the object here would destroy the one
 * explanation upstream offers.  A caller that wants the text calls
 * `re2br_regex_error` and then `re2br_regex_destroy`; a caller that does not
 * calls `re2br_regex_destroy` and nothing else.  Such a handle is otherwise
 * safe: `re2br_regex_group_count` answers -1 for it, because the constructor
 * resets `num_captures_` to -1 and assigns the real count only on success
 * (`re2/re2.cc:223,276`), and `re2br_match` refuses it. */
Re2BridgeStatus re2br_compile(const Re2BridgeOptions* options,
                              const char* pattern, size_t pattern_len,
                              Re2BridgeRegex** out_regex);

/* `RE2::error()` (`re2/re2.h` -- the accessor pair declared with `ok()`),
 * borrowed from `regex` and owned by it: the returned pointer stays valid until
 * `re2br_regex_destroy(regex)` and must not be freed by the caller.
 *
 * It is `const` here because no path through this header writes through it:
 * upstream returns a `const std::string&` out of a `const` member and this
 * function only reads.  It is never NULL for a live handle, and it is the empty
 * string for a regex that compiled, so a caller tests `re2br_regex_error`
 * against `""` rather than against NULL. */
const char* re2br_regex_error(const Re2BridgeRegex* regex);

/* `RE2::NumberOfCapturingGroups()` (`re2/re2.h:547-551`): the number of
 * parenthesised sub-expressions, excluding the overall match.  It is -1 for a
 * handle whose pattern was refused, because the constructor resets
 * `num_captures_` to -1 and assigns the real count only once the parse
 * succeeds (`re2/re2.cc:223,276`).  It is the count a caller needs to size a
 * span array, because `RE2::Match` wants `1 + NumberOfCapturingGroups()`
 * entries (`re2/re2.cc:692-694`).
 *
 * A negative answer is refused by `re2br_match` rather than turned into a
 * one-element span array, so a refused pattern cannot be matched with. */
int re2br_regex_group_count(const Re2BridgeRegex* regex);

/* Frees a handle.  NULL is accepted and ignored. */
void re2br_regex_destroy(Re2BridgeRegex* regex);

/* ---------------------------------------------------------------------------
 * Match
 * ------------------------------------------------------------------------- */

/* `RE2::Match` (`re2/re2.h:563-589`), with the span buffer made explicit.
 *
 * `anchor` is one of the RE2BRIDGE_ANCHOR_* constants.  `text` is `text_len`
 * bytes at `text` and need not be NUL-terminated.  `startpos` and `endpos` are
 * byte offsets into `text`, exactly as upstream documents them.
 *
 * The span count is always `1 + RE2::NumberOfCapturingGroups()`
 * (`re2/re2.cc:692-694`), and `*out_span_count` always receives it, on every
 * status, so one sizing call sizes every later call against the same regex.
 * `spans` may be NULL, or `spans_cap` may be 0, for that sizing call.
 *
 * The bound check is this file's, not upstream's, and it exists because
 * upstream does not make the distinction: `RE2::Match` tests
 * `startpos > endpos || endpos > text.size()` and returns plain `false` for
 * both a bad offset pair and a subject that simply does not match
 * (`re2/re2.cc:670-677`).  A caller that forwarded the call could never tell a
 * programming mistake from an ordinary no-match, so the pair is rejected here
 * as `RE2BRIDGE_INVALID_ARGUMENT` before the engine runs.  `endpos` equal to
 * `text_len` is in range: upstream's own bound is `endpos > text.size()`.
 *
 * `RE2BRIDGE_NO_MATCH` leaves every span untouched, and so does
 * `RE2BRIDGE_BUFFER_TOO_SMALL`.  Upstream's own contract is that the submatch
 * array "may be clobbered even on match failure" (`re2/re2.h:573`), so no
 * caller may read a span after this status; this bridge does not clear the
 * buffer, because clearing it would be a claim about bytes the caller owns
 * that upstream never promised anything about. */
Re2BridgeStatus re2br_match(const Re2BridgeRegex* regex, int anchor,
                            const char* text, size_t text_len,
                            size_t startpos, size_t endpos,
                            Re2BridgeSpan* spans, size_t spans_cap,
                            size_t* out_span_count);

/* ---------------------------------------------------------------------------
 * Extract
 * ------------------------------------------------------------------------- */

/* `RE2::Extract` composed exactly the way upstream composes it.
 *
 * Upstream's own static `RE2::Extract` (`re2/re2.cc:542-557`) sizes a vector
 * from `1 + RE2::MaxSubmatch(rewrite)` (`re2/re2.cc:547`), matches
 * unanchored over the whole text, and hands the vector to the member
 * `RE2::Rewrite` (`re2/re2.cc:556`).  This entry point keeps that composition
 * and makes the two things upstream leaves implicit explicit: the anchor, and
 * the byte range searched.
 *
 * The rewrite template's `\0` is the whole match and `\1`..`\9` are the
 * capturing groups (`re2/re2.h:467-471`).  A group that did not take part
 * appends nothing rather than raising an error (`re2/re2.cc:1051-1053`), and
 * a group that participated and was empty appends nothing either, so the two
 * are indistinguishable in the output.
 *
 * There is no two-digit token: `RE2::MaxSubmatch` reads exactly one digit
 * after the backslash (`re2/re2.cc:1015-1021`), so `\10` is group 1 followed
 * by a literal `0`, not group 10.  A template that is malformed, or that asks
 * for a group the pattern does not have, is `RE2BRIDGE_BAD_REWRITE` and is
 * detected before any output is written -- `RE2::CheckRewriteString` is the
 * check upstream documents for exactly this (`re2/re2.h:592-599`), and its own
 * error text names the group count it wanted (`re2/re2.cc:1000-1004`).
 *
 * Two-pass like every other buffer entry point: NULL or `cap == 0` sizes,
 * a short `cap` is `RE2BRIDGE_BUFFER_TOO_SMALL` with `*out_len` still holding
 * the required byte count, and the buffer untouched.  `*out_len` never counts
 * the NUL on either entry point in this header, so a caller sizes with
 * `len + 1` everywhere and the two agree.
 *
 * `RE2BRIDGE_NO_MATCH` leaves `*out_len` at 0 and writes no output byte.
 */
Re2BridgeStatus re2br_extract(const Re2BridgeRegex* regex, int anchor,
                              const char* text, size_t text_len,
                              size_t startpos, size_t endpos,
                              const char* rewrite, size_t rewrite_len,
                              char* out, size_t out_cap, size_t* out_len);

/* `RE2::QuoteMeta` (`re2/re2.h:515-520`): escapes every metacharacter in
 * `text`, so the result used as a pattern matches exactly the input.  Two-pass
 * like every other buffer entry point, and `*out_len` excludes the NUL.
 *
 * This is `static` upstream, so it takes no handle and cannot fail on a
 * pattern; the only failure left is an allocation, which is
 * `RE2BRIDGE_OUT_OF_MEMORY`. */
Re2BridgeStatus re2br_quote_meta(const char* text, size_t text_len,
                                 char* out, size_t out_cap, size_t* out_len);

/* `RE2::CheckRewriteString` (`re2/re2.h:592-601`), asked about `rewrite` and
 * this regex's own group count.  `RE2BRIDGE_OK` guarantees the rewrite cannot
 * fail inside `re2br_extract`; `RE2BRIDGE_BAD_REWRITE` means it would, and
 * `re2br_regex_error` is not where that text lives -- upstream returns it
 * through this call's own `std::string*` (`re2/re2.cc:971-972`), so the bridge
 * checks and reports the status without inventing an error channel for the
 * message.  A caller that wants the text should call the member through its
 * own C++ code. */
Re2BridgeStatus re2br_check_rewrite(const Re2BridgeRegex* regex,
                                    const char* rewrite, size_t rewrite_len);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* RE2_BRIDGE_H_ */