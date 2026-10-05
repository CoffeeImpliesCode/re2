// SPDX-License-Identifier: BSD-3-Clause
//
// The C++ half of the RE2 bridge.
//
// Every function here is one upstream call, wrapped.  Nothing in this file
// compiles a pattern, decides an anchor, formats an offset or invents a match
// on its own behalf: it converts the C surface declared in `zig/bridge.h` into
// the arguments `RE2`'s public API actually takes, and converts that call's
// answer back.  The one place this file takes a decision upstream does not is
// `re2br_match`'s bound check, and the reason is written at that function.
//
// Why a `.cc` at all: `addTranslateC` reads `zig/bridge.h` as C, and this
// translation unit is what a C++ compiler compiles.  It is the only file in
// this package that reaches an upstream RE2 header, and it reaches them
// exactly as a consumer would -- `#include "re2/re2.h"`, not a private
// internal header.  `build.zig` therefore puts the include root on the compile
// line and not on the translation line, so a consumer that breaks against a
// changed upstream header breaks here too.

#include "re2/re2.h"

#include <limits>
#include <new>
#include <string>
#include <vector>

#include "bridge.h"

// The storage behind one opaque handle.
//
// `zig/bridge.h` declares `typedef struct Re2BridgeRegex Re2BridgeRegex;`
// with no definition, and C callers only ever see the pointer, so the
// definition belongs here, at the same global scope the header's typedef names
// and outside the anonymous namespace below.  It has to be that struct and not
// a private `Re2BridgeRegexImpl` standing in for it: `re2br_regex_destroy`
// takes a `Re2BridgeRegex*` and `delete`s it, which needs this exact type
// complete, and the whole file reads the engine through `regex->re`.
//
// `RE2` is neither copyable nor movable at this pin (`re2/re2.h:296-304`), so
// the handle owns it by construction and is created in place by
// `re2br_compile`.  There is no intermediate `RE2` on the heap to leak if this
// allocation throws.
struct Re2BridgeRegex {
  Re2BridgeRegex(absl::string_view pattern, const RE2::Options& options)
      : re(pattern, options) {}
  RE2 re;
};

namespace {


// Resolves one `Re2BridgeFlag` to the value to hand a setter.
//
// `upstream_default` is what `Options()`'s constructor initialiser list put
// there (`re2/re2.h:678-692`).  Passing it in rather than reading it back off a
// default-constructed `Options` keeps the default visible at the call site,
// next to the field that documents it in `zig/bridge.h`.
bool resolveFlag(uint8_t flag, bool upstream_default, bool* out) {
  switch (flag) {
    case RE2BRIDGE_FLAG_DEFAULT:
      *out = upstream_default;
      return true;
    case RE2BRIDGE_FLAG_ON:
      *out = true;
      return true;
    case RE2BRIDGE_FLAG_OFF:
      *out = false;
      return true;
    default:
      // Not clamped and not ignored: a caller that passed a value this header
      // does not define has a bug, and saying so is the whole point of the
      // tri-state.
      return false;
  }
}

// Fills `options` from `in`, or reports that `in` is not a value set this
// header defines.
//
// `in` may be null, meaning "every upstream default", which is the same thing
// as an all-zero struct by the rule `zig/bridge.h` states for the struct.
//
// `RE2::Options` exposes no mutable accessors at this pin -- only `x() const`
// and `set_x(bool)` pairs (`re2/re2.h:694-733`) -- so each flag is resolved to
// a plain bool first and then handed to its setter.  Writing the resolved
// default back is a no-op on the value the constructor already chose, which is
// why there is no "was it already set" bookkeeping here.
bool toOptions(const Re2BridgeOptions* in, RE2::Options* options) {
  const Re2BridgeOptions zeros{};
  const Re2BridgeOptions& src = in != nullptr ? *in : zeros;

  switch (src.encoding) {
    case RE2BRIDGE_ENCODING_DEFAULT:
      break;  // leave whatever the constructor chose, which is EncodingUTF8
    case RE2BRIDGE_ENCODING_UTF8:
      options->set_encoding(RE2::Options::EncodingUTF8);
      break;
    case RE2BRIDGE_ENCODING_LATIN1:
      options->set_encoding(RE2::Options::EncodingLatin1);
      break;
    default:
      return false;
  }

  // `max_mem == 0` means upstream's kDefaultMaxMem (`re2/re2.h:671`), so the
  // setter is simply not called: the constructor already put that value in.
  if (src.max_mem != 0) options->set_max_mem(src.max_mem);

  bool value = false;
  if (!resolveFlag(src.posix_syntax, false, &value)) return false;
  options->set_posix_syntax(value);
  if (!resolveFlag(src.longest_match, false, &value)) return false;
  options->set_longest_match(value);
  if (!resolveFlag(src.log_errors, true, &value)) return false;
  options->set_log_errors(value);
  if (!resolveFlag(src.literal, false, &value)) return false;
  options->set_literal(value);
  if (!resolveFlag(src.never_nl, false, &value)) return false;
  options->set_never_nl(value);
  if (!resolveFlag(src.dot_nl, false, &value)) return false;
  options->set_dot_nl(value);
  if (!resolveFlag(src.never_capture, false, &value)) return false;
  options->set_never_capture(value);
  if (!resolveFlag(src.case_sensitive, true, &value)) return false;
  options->set_case_sensitive(value);
  if (!resolveFlag(src.perl_classes, false, &value)) return false;
  options->set_perl_classes(value);
  if (!resolveFlag(src.word_boundary, false, &value)) return false;
  options->set_word_boundary(value);
  if (!resolveFlag(src.one_line, false, &value)) return false;
  options->set_one_line(value);
  return true;
}

// A subject pointer is usable when it is non-null, or when the caller says
// there is nothing there.  An empty pattern and an empty subject are both real
// inputs to RE2, not errors.
bool subjectOk(const char* text, size_t text_len) {
  return text != nullptr || text_len == 0;
}

bool anchorOk(int anchor) {
  return anchor == RE2BRIDGE_UNANCHORED || anchor == RE2BRIDGE_ANCHOR_START ||
         anchor == RE2BRIDGE_ANCHOR_BOTH;
}

RE2::Anchor toAnchor(int anchor) {
  switch (anchor) {
    case RE2BRIDGE_ANCHOR_START:
      return RE2::ANCHOR_START;
    case RE2BRIDGE_ANCHOR_BOTH:
      return RE2::ANCHOR_BOTH;
    default:
      return RE2::UNANCHORED;
  }
}

}  // namespace

// ---------------------------------------------------------------------------
// Compile
// ---------------------------------------------------------------------------

extern "C" void re2br_options_init(Re2BridgeOptions* out) {
  if (out == nullptr) return;
  // Every field zero is "whatever upstream does", so the all-defaults struct
  // is the zero struct.  `RE2::Options()`'s own constructor
  // (`re2/re2.h:678-692`) is what those zeros mean; nothing is written here
  // that upstream has not already written for itself.
  *out = Re2BridgeOptions{};
}

extern "C" Re2BridgeStatus re2br_compile(const Re2BridgeOptions* options,
                                         const char* pattern,
                                         size_t pattern_len,
                                         Re2BridgeRegex** out_regex) {
  if (out_regex == nullptr) return RE2BRIDGE_INVALID_ARGUMENT;
  // `out_regex` is cleared before anything can fail, so a caller that ignores
  // the status holds a null pointer rather than an indeterminate one.
  *out_regex = nullptr;

  if (!subjectOk(pattern, pattern_len)) return RE2BRIDGE_INVALID_ARGUMENT;

  RE2::Options upstream_options;
  if (!toOptions(options, &upstream_options)) return RE2BRIDGE_INVALID_ARGUMENT;

  Re2BridgeRegex* handle = nullptr;
  try {
    handle = new Re2BridgeRegex(absl::string_view(pattern, pattern_len),
                                upstream_options);
  } catch (const std::bad_alloc&) {
    return RE2BRIDGE_OUT_OF_MEMORY;
  }

  if (!handle->re.ok()) {
    // The handle is handed back anyway.  `RE2::error()` is a `const` accessor
    // on the object (`re2/re2.h:313-316`), so the message exists only for as
    // long as that object does, and destroying it here would destroy the one
    // explanation upstream offers.  This is upstream's own model: a rejected
    // pattern leaves a live `RE2` whose `ok()` is false and whose `error()` is
    // populated.  A caller that wants the text calls `re2br_regex_error` and
    // then `re2br_regex_destroy`; a caller that does not just destroys it.
    *out_regex = handle;
    return RE2BRIDGE_BAD_PATTERN;
  }

  *out_regex = handle;
  return RE2BRIDGE_OK;
}

extern "C" const char* re2br_regex_error(const Re2BridgeRegex* regex) {
  if (regex == nullptr) return "";
  return regex->re.error().c_str();
}

extern "C" int re2br_regex_group_count(const Re2BridgeRegex* regex) {
  if (regex == nullptr) return -1;
  return regex->re.NumberOfCapturingGroups();
}

extern "C" void re2br_regex_destroy(Re2BridgeRegex* regex) {
  delete regex;  // null is accepted and ignored, which delete does for us
}

// ---------------------------------------------------------------------------
// Match
// ---------------------------------------------------------------------------

extern "C" Re2BridgeStatus re2br_match(const Re2BridgeRegex* regex, int anchor,
                                       const char* text, size_t text_len,
                                       size_t startpos, size_t endpos,
                                       Re2BridgeSpan* spans, size_t spans_cap,
                                       size_t* out_span_count) {
  if (regex == nullptr || out_span_count == nullptr)
    return RE2BRIDGE_INVALID_ARGUMENT;
  if (!anchorOk(anchor)) return RE2BRIDGE_INVALID_ARGUMENT;
  if (!subjectOk(text, text_len)) return RE2BRIDGE_INVALID_ARGUMENT;

  // The one check this file makes that upstream does not.
  //
  // `RE2::Match` folds a bad offset pair into an ordinary non-match:
  // `startpos > endpos || endpos > text.size()` logs and returns false
  // (`re2/re2.cc:670-677`), which is the same value it returns for a subject
  // that simply does not match.  Forwarding that would leave a caller unable
  // to tell a programming mistake from an answer, so the pair is refused here,
  // before the engine runs, using the same bound upstream uses: `endpos` equal
  // to `text_len` is in range.
  if (startpos > endpos || endpos > text_len) return RE2BRIDGE_INVALID_ARGUMENT;

  const int groups = regex->re.NumberOfCapturingGroups();
  if (groups < 0) return RE2BRIDGE_INVALID_ARGUMENT;

  // `RE2::Match` clamps its own vector to `1 + NumberOfCapturingGroups()`
  // (`re2/re2.cc:692-694`); this is that count, reported on every status so a
  // single sizing call sizes every later call against the same regex.
  const size_t required = static_cast<size_t>(groups) + 1;
  if (required > static_cast<size_t>(std::numeric_limits<int>::max()))
    return RE2BRIDGE_INVALID_ARGUMENT;
  *out_span_count = required;

  if (spans == nullptr || spans_cap == 0) return RE2BRIDGE_OK;  // sizing call
  if (spans_cap < required) return RE2BRIDGE_BUFFER_TOO_SMALL;

  std::vector<absl::string_view> vec(required);
  const absl::string_view subject(text, text_len);

  if (!regex->re.Match(subject, startpos, endpos, toAnchor(anchor), vec.data(),
                       static_cast<int>(required)))
    return RE2BRIDGE_NO_MATCH;

  for (size_t i = 0; i < required; ++i) {
    if (vec[i].data() == nullptr) {
      // Upstream's own signal for a group with no range is a
      // default-constructed view (`re2/re2.h:571-572`).  It cannot distinguish
      // "did not participate" from "participated and was empty"; both are
      // reported as no range, which is what a NULL pointer can honestly say.
      spans[i].start = RE2BRIDGE_SPAN_NO_MATCH;
      spans[i].end = RE2BRIDGE_SPAN_NO_MATCH;
      continue;
    }
    // The view is a subview of `subject`, so this is its offset in the
    // caller's own buffer.
    spans[i].start = static_cast<size_t>(vec[i].data() - subject.data());
    spans[i].end = spans[i].start + vec[i].size();
  }
  return RE2BRIDGE_OK;
}

// ---------------------------------------------------------------------------
// Extract
// ---------------------------------------------------------------------------

extern "C" Re2BridgeStatus re2br_extract(const Re2BridgeRegex* regex,
                                         int anchor, const char* text,
                                         size_t text_len, size_t startpos,
                                         size_t endpos, const char* rewrite,
                                         size_t rewrite_len, char* out,
                                         size_t out_cap, size_t* out_len) {
  if (regex == nullptr || out_len == nullptr) return RE2BRIDGE_INVALID_ARGUMENT;
  if (!anchorOk(anchor)) return RE2BRIDGE_INVALID_ARGUMENT;
  if (!subjectOk(text, text_len)) return RE2BRIDGE_INVALID_ARGUMENT;
  if (!subjectOk(rewrite, rewrite_len)) return RE2BRIDGE_INVALID_ARGUMENT;
  if (startpos > endpos || endpos > text_len) return RE2BRIDGE_INVALID_ARGUMENT;

  *out_len = 0;

  const absl::string_view subject(text, text_len);
  const absl::string_view template_view(rewrite, rewrite_len);

  // Upstream documents this as the check that guarantees `Extract` cannot fail
  // on a bad rewrite (`re2/re2.h:592-599`).  Its own message is not returned
  // here: this header has one status for "the rewrite is wrong", and inventing
  // a second error channel for the text would be a claim about a buffer the
  // caller never supplied.
  std::string rewrite_error;
  if (!regex->re.CheckRewriteString(template_view, &rewrite_error))
    return RE2BRIDGE_BAD_REWRITE;

  // Upstream's own composition (`re2/re2.cc:542-557`): size the vector from
  // the rewrite template, not from the pattern's group count.
  // `CheckRewriteString` above has already established that this fits inside
  // the pattern.
  const int max_submatch = RE2::MaxSubmatch(template_view);
  if (max_submatch < 0) return RE2BRIDGE_BAD_REWRITE;
  const size_t nvec = static_cast<size_t>(max_submatch) + 1;
  if (nvec > static_cast<size_t>(std::numeric_limits<int>::max()))
    return RE2BRIDGE_BAD_REWRITE;

  std::vector<absl::string_view> vec(nvec);
  if (!regex->re.Match(subject, startpos, endpos, toAnchor(anchor), vec.data(),
                       static_cast<int>(nvec)))
    return RE2BRIDGE_NO_MATCH;

  std::string result;
  if (!regex->re.Rewrite(&result, template_view, vec.data(),
                         static_cast<int>(nvec)))
    return RE2BRIDGE_BAD_REWRITE;

  *out_len = result.size();
  if (out == nullptr || out_cap == 0) return RE2BRIDGE_OK;  // sizing call
  // Room for the bytes and the NUL the caller will append.
  if (out_cap < result.size() + 1) return RE2BRIDGE_BUFFER_TOO_SMALL;

  result.copy(out, result.size());
  out[result.size()] = '\0';
  return RE2BRIDGE_OK;
}

extern "C" Re2BridgeStatus re2br_quote_meta(const char* text, size_t text_len,
                                            char* out, size_t out_cap,
                                            size_t* out_len) {
  if (out_len == nullptr) return RE2BRIDGE_INVALID_ARGUMENT;
  if (!subjectOk(text, text_len)) return RE2BRIDGE_INVALID_ARGUMENT;

  *out_len = 0;

  std::string quoted;
  try {
    quoted = RE2::QuoteMeta(absl::string_view(text, text_len));
  } catch (const std::bad_alloc&) {
    return RE2BRIDGE_OUT_OF_MEMORY;
  }

  *out_len = quoted.size();
  if (out == nullptr || out_cap == 0) return RE2BRIDGE_OK;  // sizing call
  if (out_cap < quoted.size() + 1) return RE2BRIDGE_BUFFER_TOO_SMALL;

  quoted.copy(out, quoted.size());
  out[quoted.size()] = '\0';
  return RE2BRIDGE_OK;
}

extern "C" Re2BridgeStatus re2br_check_rewrite(const Re2BridgeRegex* regex,
                                               const char* rewrite,
                                               size_t rewrite_len) {
  if (regex == nullptr) return RE2BRIDGE_INVALID_ARGUMENT;
  if (!subjectOk(rewrite, rewrite_len)) return RE2BRIDGE_INVALID_ARGUMENT;

  std::string rewrite_error;
  return regex->re.CheckRewriteString(absl::string_view(rewrite, rewrite_len),
                                      &rewrite_error)
             ? RE2BRIDGE_OK
             : RE2BRIDGE_BAD_REWRITE;
}