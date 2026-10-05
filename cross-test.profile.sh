# cross-test profile for the RE2 Zig package.
#
# `cross-test` discovers this file when it is run from the package root and
# sources it as trusted Bash before it computes any default. Only variable
# assignments belong here: no command substitution, no runner list, no artifact
# hooks, no path to a particular machine.
#
# This package is driven in the standard build mode, where for every selected
# target the harness runs
#
#     zig build test -Dtarget=<target>
#
# through its own build runner. That runner is what supplies native or foreign
# execution, and what turns a foreign run into a reported skip when no runner
# exists for the target -- so the build script has to expose its run step
# unconditionally and leave the answer to the runner. `CROSS_BUILD_STEP` is
# spelled out rather than left to the harness default so that the step this
# package is gated by is stated in the package itself.
#
# The matrix is deliberately left alone: no `CROSS_MATRIX` and no `TARGETS` are
# defined, so the full published 53-platform Zig 0.16.0 tier table applies. The
# matrix belongs on the harness command line, where `--targets` selects from the
# active table and never adds to it.
#
# `-Doptimize` is not set either. The gate is the default Debug build; a
# caller that wants ReleaseSafe passes it as a `--` build argument, which is
# appended to this harness's command and is not managed here.
#
# Delivery is the default: `-Dlinkage` is not set here either, so every cell
# builds and runs the three static archives -- libre2.a, libre2bridge.a and
# libabsl.a -- which is the linkage policy this SDK has and the only delivery
# every target in the 53-platform table supports. The shared form is a delivery
# change and not a compile-only one -- `libre2bridge.so.0` resolves
# `libre2.so.11` and the Abseil shared object beside it through `$ORIGIN` at
# load time -- so it is gated by the `native` matrix in
# `.github/workflows/verify.yml` (the `*-shared` rows) rather than by a target
# list here. Upstream's own SONAME is 11 (`vendor/re2/CMakeLists.txt:43` sets
# `set(SONAME 11)`), and `re2.pc.in:7` publishes it as `Version: @SONAME@.0.0`,
# so the shared name is not this fork's to choose.
#
# A whole-table `-Dlinkage=dynamic` run is not available and is not this
# harness's to arrange: `wasm32-wasi` is in the published tier table and has no
# dynamic linker, so the shared delivery has no route for that cell. Where that
# boundary is drawn is the build graph's own rule and this profile does not
# second-guess it. Cells that want the shared delivery pass
# `-Dlinkage=dynamic` as a `--` build argument, which this harness appends and
# does not manage.
#
# `-Druntime` is likewise not managed here. It selects how the facade reaches
# the library rather than which library is delivered, it is orthogonal to
# `-Dlinkage`, and the same `--` argument carries it.
#
# One target's graph is 152 Abseil plus 22 RE2 translation units, the C bridge
# and the translated headers. Abseil's `synchronization` library and its CCTZ
# timezone sources are the largest parts of that 152, and every matrix cell
# compiles all of them from cold. One in-build job leaves a loaded host idle for
# most of that, and the harness default of 900 seconds is not much headroom for
# it. Both figures below are defaults only: the driver's own `--build-jobs`,
# `--build-timeout` and `--timeout` still override them.
CROSS_BUILD_STEP=test
CROSS_BUILD_JOBS=4
CROSS_BUILD_TIMEOUT=2400
CROSS_TIMEOUT=1800
