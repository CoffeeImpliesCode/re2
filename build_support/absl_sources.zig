// SPDX-License-Identifier: BSD-3-Clause
//! The Abseil translation units this fork compiles, and nothing else.
//!
//! Provenance
//! ----------
//! Every path below is copied out of an `absl_cc_library(... srcs ...)` block
//! of the vendored Abseil tree at `vendor/abseil-cpp`, which is the
//! `20250512.1` LTS release RE2's own `MODULE.bazel:16` names -- the version
//! the upstream tree at `vendor/re2` declares it needs.  The tag commit is
//! `76bb24329e8bf5f39704eb10d21b9a80befa7c81`.
//!
//! Why the list is enumerated rather than globbed
//! ---------------------------------------------
//! A glob over `vendor/abseil-cpp/absl/**/*.cc` would pick up every
//! `*_test.cc`, every `*_benchmark.cc`, and the Abseil "test helper"
//! translation units that are declared `testonly = True`.  Those need
//! GoogleTest, which this package deliberately does not require: `zig build`
//! must not download or demand a test framework.  Enumerating the upstream
//! `srcs` lists is what makes "the library, without its tests" a decision
//! recorded in this repository rather than an accident of a file-name
//! pattern.
//!
//! The nineteen units excluded on that basis, with the declaration that
//! excluded each one, are named in `UPSTREAM.sha256`'s group D preamble and
//! again in `NOTICE.md`.  The rule is mechanical and was applied by reading
//! the `absl_cc_library` blocks of the twenty-five `absl/**/BUILD.bazel` files
//! in this tree: a unit is dropped when its own block says
//! `testonly = True`, or names a `GTest::` dependency, or carries
//! `tags = ["testutil"]`.
//!
//! This is a narrower set than the s2geometry fork compiles, and for one
//! reason only: this is a different Abseil release.  Upstream marks
//! `absl/random/internal/chi_square.cc` and
//! `absl/random/internal/distribution_test_util.cc` as `testonly = True` at
//! `20250512.1`, so RE2's declared dependency does not need them either.  The
//! s2geometry fork keeps two files with those same names because at
//! `20250814.1` upstream declares them in
//! `absl_cc_library(random_internal_distribution_test_util)` with no
//! `testonly` marker.
//!
//! Platform variants
//! -----------------
//! Upstream declares every platform variant of a given unit in the same block
//! and lets the source's own `#ifdef` pick one, so this list is target
//! independent.  `crc_memcpy_fallback.cc` and
//! `crc_memcpy_x86_arm_combined.cc`, and all five `*_waiter.cc` files, are each
//! listed by their own `absl_cc_library` block unconditionally.  Adding one of
//! them "for this target only" would be a build decision upstream does not
//! make.  The genuinely target-selected Abseil settings are compiler flags,
//! not source files; see `platform_flags.zig`.

/// Abseil release whose sources are vendored at `vendor/abseil-cpp`.
pub const version = "20250512.1";

/// Commit of the vendored Abseil tree.
pub const commit = "76bb24329e8bf5f39704eb10d21b9a80befa7c81";

/// SHA-256 of the GitHub tarball for the pinned tag.
pub const tarball_sha256 =
    "9b7a064305e9fd94d124ffa6cc358592eb42b5da588fb4e07d09254aa40086db";

/// Directory of the vendored Abseil tree, relative to the package root.
///
/// This is the include root: sources spell their headers `absl/base/config.h`.
pub const include_dir = "vendor/abseil-cpp";

/// Every Abseil library translation unit this fork compiles.
pub const sources = [_][]const u8{
    "vendor/abseil-cpp/absl/base/internal/cycleclock.cc",
    "vendor/abseil-cpp/absl/base/internal/low_level_alloc.cc",
    "vendor/abseil-cpp/absl/base/internal/poison.cc",
    "vendor/abseil-cpp/absl/base/internal/raw_logging.cc",
    "vendor/abseil-cpp/absl/base/internal/spinlock.cc",
    "vendor/abseil-cpp/absl/base/internal/spinlock_wait.cc",
    "vendor/abseil-cpp/absl/base/internal/strerror.cc",
    "vendor/abseil-cpp/absl/base/internal/sysinfo.cc",
    "vendor/abseil-cpp/absl/base/internal/thread_identity.cc",
    "vendor/abseil-cpp/absl/base/internal/throw_delegate.cc",
    "vendor/abseil-cpp/absl/base/internal/tracing.cc",
    "vendor/abseil-cpp/absl/base/internal/unscaledcycleclock.cc",
    "vendor/abseil-cpp/absl/base/log_severity.cc",
    "vendor/abseil-cpp/absl/container/internal/hashtablez_sampler.cc",
    "vendor/abseil-cpp/absl/container/internal/hashtablez_sampler_force_weak_definition.cc",
    "vendor/abseil-cpp/absl/container/internal/raw_hash_set.cc",
    "vendor/abseil-cpp/absl/crc/crc32c.cc",
    "vendor/abseil-cpp/absl/crc/internal/cpu_detect.cc",
    "vendor/abseil-cpp/absl/crc/internal/crc.cc",
    "vendor/abseil-cpp/absl/crc/internal/crc_cord_state.cc",
    "vendor/abseil-cpp/absl/crc/internal/crc_memcpy_fallback.cc",
    "vendor/abseil-cpp/absl/crc/internal/crc_memcpy_x86_arm_combined.cc",
    "vendor/abseil-cpp/absl/crc/internal/crc_non_temporal_memcpy.cc",
    "vendor/abseil-cpp/absl/crc/internal/crc_x86_arm_combined.cc",
    "vendor/abseil-cpp/absl/debugging/failure_signal_handler.cc",
    "vendor/abseil-cpp/absl/debugging/internal/address_is_readable.cc",
    "vendor/abseil-cpp/absl/debugging/internal/decode_rust_punycode.cc",
    "vendor/abseil-cpp/absl/debugging/internal/demangle.cc",
    "vendor/abseil-cpp/absl/debugging/internal/demangle_rust.cc",
    "vendor/abseil-cpp/absl/debugging/internal/elf_mem_image.cc",
    "vendor/abseil-cpp/absl/debugging/internal/examine_stack.cc",
    "vendor/abseil-cpp/absl/debugging/internal/utf8_for_code_point.cc",
    "vendor/abseil-cpp/absl/debugging/internal/vdso_support.cc",
    "vendor/abseil-cpp/absl/debugging/leak_check.cc",
    "vendor/abseil-cpp/absl/debugging/stacktrace.cc",
    "vendor/abseil-cpp/absl/debugging/symbolize.cc",
    "vendor/abseil-cpp/absl/flags/commandlineflag.cc",
    "vendor/abseil-cpp/absl/flags/internal/commandlineflag.cc",
    "vendor/abseil-cpp/absl/flags/internal/flag.cc",
    "vendor/abseil-cpp/absl/flags/internal/private_handle_accessor.cc",
    "vendor/abseil-cpp/absl/flags/internal/program_name.cc",
    "vendor/abseil-cpp/absl/flags/internal/usage.cc",
    "vendor/abseil-cpp/absl/flags/marshalling.cc",
    "vendor/abseil-cpp/absl/flags/parse.cc",
    "vendor/abseil-cpp/absl/flags/reflection.cc",
    "vendor/abseil-cpp/absl/flags/usage.cc",
    "vendor/abseil-cpp/absl/flags/usage_config.cc",
    "vendor/abseil-cpp/absl/hash/internal/city.cc",
    "vendor/abseil-cpp/absl/hash/internal/hash.cc",
    "vendor/abseil-cpp/absl/hash/internal/low_level_hash.cc",
    "vendor/abseil-cpp/absl/log/die_if_null.cc",
    "vendor/abseil-cpp/absl/log/flags.cc",
    "vendor/abseil-cpp/absl/log/globals.cc",
    "vendor/abseil-cpp/absl/log/initialize.cc",
    "vendor/abseil-cpp/absl/log/internal/check_op.cc",
    "vendor/abseil-cpp/absl/log/internal/conditions.cc",
    "vendor/abseil-cpp/absl/log/internal/fnmatch.cc",
    "vendor/abseil-cpp/absl/log/internal/globals.cc",
    "vendor/abseil-cpp/absl/log/internal/log_format.cc",
    "vendor/abseil-cpp/absl/log/internal/log_message.cc",
    "vendor/abseil-cpp/absl/log/internal/log_sink_set.cc",
    "vendor/abseil-cpp/absl/log/internal/nullguard.cc",
    "vendor/abseil-cpp/absl/log/internal/proto.cc",
    "vendor/abseil-cpp/absl/log/internal/structured_proto.cc",
    "vendor/abseil-cpp/absl/log/internal/vlog_config.cc",
    "vendor/abseil-cpp/absl/log/log_sink.cc",
    "vendor/abseil-cpp/absl/numeric/int128.cc",
    "vendor/abseil-cpp/absl/profiling/internal/exponential_biased.cc",
    "vendor/abseil-cpp/absl/profiling/internal/periodic_sampler.cc",
    "vendor/abseil-cpp/absl/random/discrete_distribution.cc",
    "vendor/abseil-cpp/absl/random/gaussian_distribution.cc",
    "vendor/abseil-cpp/absl/random/internal/entropy_pool.cc",
    "vendor/abseil-cpp/absl/random/internal/nanobenchmark.cc",
    "vendor/abseil-cpp/absl/random/internal/randen.cc",
    "vendor/abseil-cpp/absl/random/internal/randen_detect.cc",
    "vendor/abseil-cpp/absl/random/internal/randen_hwaes.cc",
    "vendor/abseil-cpp/absl/random/internal/randen_round_keys.cc",
    "vendor/abseil-cpp/absl/random/internal/randen_slow.cc",
    "vendor/abseil-cpp/absl/random/internal/seed_material.cc",
    "vendor/abseil-cpp/absl/random/seed_gen_exception.cc",
    "vendor/abseil-cpp/absl/random/seed_sequences.cc",
    "vendor/abseil-cpp/absl/status/internal/status_internal.cc",
    "vendor/abseil-cpp/absl/status/status.cc",
    "vendor/abseil-cpp/absl/status/status_payload_printer.cc",
    "vendor/abseil-cpp/absl/status/statusor.cc",
    "vendor/abseil-cpp/absl/strings/ascii.cc",
    "vendor/abseil-cpp/absl/strings/charconv.cc",
    "vendor/abseil-cpp/absl/strings/cord.cc",
    "vendor/abseil-cpp/absl/strings/cord_analysis.cc",
    "vendor/abseil-cpp/absl/strings/escaping.cc",
    "vendor/abseil-cpp/absl/strings/internal/charconv_bigint.cc",
    "vendor/abseil-cpp/absl/strings/internal/charconv_parse.cc",
    "vendor/abseil-cpp/absl/strings/internal/cord_internal.cc",
    "vendor/abseil-cpp/absl/strings/internal/cord_rep_btree.cc",
    "vendor/abseil-cpp/absl/strings/internal/cord_rep_btree_navigator.cc",
    "vendor/abseil-cpp/absl/strings/internal/cord_rep_btree_reader.cc",
    "vendor/abseil-cpp/absl/strings/internal/cord_rep_consume.cc",
    "vendor/abseil-cpp/absl/strings/internal/cord_rep_crc.cc",
    "vendor/abseil-cpp/absl/strings/internal/cordz_functions.cc",
    "vendor/abseil-cpp/absl/strings/internal/cordz_handle.cc",
    "vendor/abseil-cpp/absl/strings/internal/cordz_info.cc",
    "vendor/abseil-cpp/absl/strings/internal/cordz_sample_token.cc",
    "vendor/abseil-cpp/absl/strings/internal/damerau_levenshtein_distance.cc",
    "vendor/abseil-cpp/absl/strings/internal/escaping.cc",
    "vendor/abseil-cpp/absl/strings/internal/memutil.cc",
    "vendor/abseil-cpp/absl/strings/internal/ostringstream.cc",
    "vendor/abseil-cpp/absl/strings/internal/str_format/arg.cc",
    "vendor/abseil-cpp/absl/strings/internal/str_format/bind.cc",
    "vendor/abseil-cpp/absl/strings/internal/str_format/extension.cc",
    "vendor/abseil-cpp/absl/strings/internal/str_format/float_conversion.cc",
    "vendor/abseil-cpp/absl/strings/internal/str_format/output.cc",
    "vendor/abseil-cpp/absl/strings/internal/str_format/parser.cc",
    "vendor/abseil-cpp/absl/strings/internal/stringify_sink.cc",
    "vendor/abseil-cpp/absl/strings/internal/utf8.cc",
    "vendor/abseil-cpp/absl/strings/match.cc",
    "vendor/abseil-cpp/absl/strings/numbers.cc",
    "vendor/abseil-cpp/absl/strings/str_cat.cc",
    "vendor/abseil-cpp/absl/strings/str_replace.cc",
    "vendor/abseil-cpp/absl/strings/str_split.cc",
    "vendor/abseil-cpp/absl/strings/string_view.cc",
    "vendor/abseil-cpp/absl/strings/substitute.cc",
    "vendor/abseil-cpp/absl/synchronization/barrier.cc",
    "vendor/abseil-cpp/absl/synchronization/blocking_counter.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/create_thread_identity.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/futex_waiter.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/graphcycles.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/kernel_timeout.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/per_thread_sem.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/pthread_waiter.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/sem_waiter.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/stdcpp_waiter.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/waiter_base.cc",
    "vendor/abseil-cpp/absl/synchronization/internal/win32_waiter.cc",
    "vendor/abseil-cpp/absl/synchronization/mutex.cc",
    "vendor/abseil-cpp/absl/synchronization/notification.cc",
    "vendor/abseil-cpp/absl/time/civil_time.cc",
    "vendor/abseil-cpp/absl/time/clock.cc",
    "vendor/abseil-cpp/absl/time/duration.cc",
    "vendor/abseil-cpp/absl/time/format.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/civil_time_detail.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_fixed.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_if.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_impl.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_info.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_libc.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_lookup.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/time_zone_posix.cc",
    "vendor/abseil-cpp/absl/time/internal/cctz/src/zone_info_source.cc",
    "vendor/abseil-cpp/absl/time/time.cc",
};

/// The Abseil units the `testonly`/GoogleTest rule excluded, each with the
/// declaration that excluded it.  Kept as data rather than only as prose so
/// `UPSTREAM.sha256` and a reader of `build.zig` can both check that the
/// exclusion is the one upstream made and not one this fork invented.
pub const excluded = [_]struct { path: []const u8, reason: []const u8 }{
    .{ .path = "vendor/abseil-cpp/absl/base/internal/atomic_hook_test_helper.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/base/internal/exception_safety_testing.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/base/internal/scoped_set_env.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/base/internal/spinlock_benchmark.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/base/spinlock_test_common.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/container/internal/hash_generator_testing.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/container/internal/test_instance_tracker.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/debugging/internal/stack_consumption.cc", .reason = "testonly = 1" },
    .{ .path = "vendor/abseil-cpp/absl/log/internal/test_actions.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/log/internal/test_helpers.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/log/internal/test_matchers.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/log/scoped_mock_log.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/random/internal/chi_square.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/random/internal/distribution_test_util.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/status/internal/status_matchers.cc", .reason = "testonly = 1" },
    .{ .path = "vendor/abseil-cpp/absl/strings/internal/pow10_helper.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/synchronization/internal/per_thread_sem_test.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/synchronization/mutex_benchmark.cc", .reason = "testonly = True" },
    .{ .path = "vendor/abseil-cpp/absl/time/internal/test_util.cc", .reason = "testonly = True" },
};
