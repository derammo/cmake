# cmake

my cmake scripts as a submodule

[![validate with cmake_tests](https://github.com/derammo/cmake/actions/workflows/validate_with_cmake_tests.yml/badge.svg)](https://github.com/derammo/cmake/actions/workflows/validate_with_cmake_tests.yml)

## installation

from the top of any project, run:

```
cp Makefile Makefile.orig
git submodule add https://github.com/derammo/cmake
make -f cmake/setup.make root
make
```

then edit the top level CMakeLists.txt to add your project name, vendor, and contact info

## make targets (POSIX: Linux, macOS, etc.)

`cmake/setup.make root` generates a top-level `Makefile` that `include`s `cmake/main.make`, which provides the following targets. Run them from the project root.

| target           | what it does                                                                                                               |
|------------------|----------------------------------------------------------------------------------------------------------------------------|
| `all` (default)  | same as `release`                                                                                                          |
| `release`        | configure and build `<Platform>/Release` (e.g. `Linux/Release`, `Darwin/Release`)                                          |
| `debug`          | configure and build `<Platform>/Debug`                                                                                     |
| `relWithDebInfo` | configure and build `<Platform>/RelWithDebInfo`                                                                            |
| `configure`      | configure all build types, without building, to be used for development of cmake files                                     |
| `package`        | build Release, then run CPack (`make package`) in the Release build dir                                                    |
| `docker`         | build Release, then run the `docker` custom target if the project defines one (non-fatal if missing)                       |
| `test`           | build Debug, then run every registered test through `ctest --output-on-failure` (gtest, npm, maven, ... see below)         |
| `test-<label>`   | like `test`, restricted to one provider label, e.g. `make test-npm`, `make test-jest`                                      |
| `lint`           | build Debug (configure only with `DERAMMO_SKIP_BUILD=1`), then run the `lint` tests in parallel, see code quality below    |
| `format`         | rewrite the sources in place with every formatter the build registered, in the first configured tree, see formatting below |
| `npm-update`     | move every npm dependency of every npm root to the newest version its range allows, see npm packages below                 |
| `npm-outdated`   | print what `npm-update` would change, changing nothing                                                                     |
| `clean`          | run `make clean` inside any existing `<Platform>/{Release,RelWithDebInfo,Debug}` build dir (keeps the dirs themselves)     |
| `squeaky`        | delete `<Platform>/`, the `build` link and `Windows/` entirely, removing all build artifacts                               |
| `info`           | print the detected platform and the inputs main.make watches for regeneration                                              |
| `probe`          | print just the detected platform                                                                                           |
| `trace`          | re-run cmake with `--trace` into `<Platform>/Debug` for debugging CMake logic                                              |

`<Platform>` is the output of `uname -s` (`Linux`, `Darwin`, etc.), so build trees for multiple platforms can coexist in the same source tree.

Every target that configures a build tree also keeps a symbolic link `build` to `<Platform>` at the project root, so a path such as `build/Debug/compile_commands.json` names the current platform's tree without spelling the platform; editor settings can point at the compile database there. A project that has its own file or directory called `build` keeps it, and gets no link.

Several of the per-platform paths can also be invoked directly:

```
make Linux/Release/Makefile
make Linux/Debug/Makefile
make Darwin/Debug/Makefile
```

## Windows (native, via Visual Studio)

Windows does not use `make` — the equivalents live in the `cmake\` submodule and are run from the project root:

| command          | equivalent POSIX target | what it does                                                           |
|------------------|-------------------------|------------------------------------------------------------------------|
| `cmake\make.cmd` | `make` (all configs)    | generate `Windows\` build tree via `cmake -B Windows -A x64`           |
| `cmake\open.cmd` | —                       | run `cmake\make.cmd` then open every generated `.sln` in Visual Studio |
| `cmake\test.cmd` | `make test`             | run `ctest --output-on-failure` inside the `Windows\` build tree       |

In particular, **there is no `make test` on Windows** — use `cmake\test.cmd` instead.

The Visual Studio generator writes no compile database, so there configure disables the clang-tidy check with `tidy: disabled (the Visual Studio <version> generator writes no compile database)`, which `-DDERAMMO_LINT_REQUIRED=ON` makes fatal; the `lint_format` and `lint_size` tests run as usual (see code quality below).

## npm packages

A package whose `package.json` names a dependency as `file:<path>.tgz` consumes a tarball that `npm pack` left in the directory of the package that built it (the `_package_template_tarball.json` template packs on every build and keeps a `<name>-current.tgz` link to the result). The lock file records which build of the tarball the consumer installed, and `npm install` keeps to it, as with any dependency; moving to a newer build is `npm update`. This build always wants the latest locally built packages, so it orders the consumer after the provider and runs `npm update <names>` for the consumer's tarball dependencies as the first step of its build target, visible as a plain command in the generated build; for a workspace member this runs from the workspace root with `--workspace <member>`, since npm run in a member directory would treat the member as a project of its own. The package manifests carry no `prebuild` script for this.

Registry dependencies move only on request: `make npm-update` runs `npm update` in every npm root the build knows, each workspace root over itself and its members and each package outside a workspace, taking every dependency to the newest version its declared range allows; `make npm-outdated` prints what that would change, as `npm update --dry-run`, and changes nothing. The ranges live in the package templates; the lock files record what the update chose.

### quick iteration (`QUICK`)

Configuring a build tree with `-DQUICK=ON` (default `OFF`, e.g. `cmake -DQUICK=ON build/Release`) makes every npm package build target run its steps through `cmake/scripts/npm_quick_build.ts`, which skips all of them — the per-package `npm update` and `npm install` included — when the package is demonstrably up to date. The check follows the package's `build` script chain to the single `tsc -p <config>` it runs and compares against a stamp written when the last build completed through the script: the inputs recorded in that configuration's incremental `.tsbuildinfo`, the tsconfig extends chain, `package.json` itself, the nearest `package-lock.json` (by content, since an install freshens its timestamp without changing it), and every `file:...tgz` tarball dependency, so a rebuilt provider tarball makes its consumers build. A source file the build info does not list yet, a missing output (`outDir`, or the `<name>-current.tgz` link of a tarball package), or anything the analysis does not recognize — a `build` script that is not a plain tsc project build, a non-incremental configuration — also forces a build. The stamp is a JSON file named `tsconfig.<name>.quickstamp.json` next to the build info; the gitignore, `clean` script, and `npm_squeaky` patterns remove `*.quickstamp.json` wherever they remove tsbuildinfo files.

An input that none of those records can show — for example an indirect dependency whose refresh only an unconditional `npm install` would surface — is invisible to the check, so a quick build can wrongly skip; that is the trade for fast iteration, and why the switch is off by default and not for release or CI builds. When a skip looks wrong, reconfigure with `-DQUICK=OFF` (or delete the package's `tsconfig.*.tsbuildinfo` files) and build once. The shared install of a workspace root still runs on every build; only the member builds are skipped.

## test providers

All testing goes through CTest. Each kind of test support registers the tests it finds with `add_test()` and labels them with the provider name, so the generated `test` target (and `make test` / `cmake\test.cmd`) runs everything, and `ctest -L <label>` or `make test-<label>` runs one kind. `ctest --print-labels` in a build directory lists what a project registered.

| provider file         | registers                                                                                                           | labels                                                                           |
|-----------------------|---------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------|
| `derammo_gtest.cmake` | one test per Google Test case, discovered from each `gtest/` target                                                 | `gtest`                                                                          |
| `derammo_npm.cmake`   | `npm run test` per package: standalone packages register themselves, a workspace root registers one test per member | `npm`, plus the framework found in `devDependencies` (`vitest`, `jest`, `mocha`) |
| `derammo_maven.cmake` | `mvn test` for each `derammo_maven_build()`                                                                         | `maven`                                                                          |
| `derammo_lint.cmake`  | `lint_format/<path>`, `lint_tidy/<path>`, `lint_size/<path>` per C and C++ file, see code quality below             | `lint`                                                                           |

Test output is kept plain for the captured log (no color: `--gtest_color=no`, `NO_COLOR=1` in the environment of npm tests, `mvn --batch-mode`), and every provider also writes JUnit XML into `<Platform>/<Config>/junit/`:

| provider | JUnit XML                                                                                                                                                                                                                                                                                                                                                       |
|----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| ctest    | `junit/ctest.xml`, the whole run                                                                                                                                                                                                                                                                                                                                |
| gtest    | `junit/<test>.xml`, one file per test case                                                                                                                                                                                                                                                                                                                      |
| npm      | `junit/<test>.xml`: the test's environment carries `DERAMMO_JUNIT_FILE`, which the generated `vitest.config.ts` turns into a `junit` reporter; jest packages get `JEST_JUNIT_OUTPUT_FILE` for the `jest-junit` reporter in the template; a package with no known framework is assumed to use `node --test` and gets the `junit` reporter through `NODE_OPTIONS` |
| maven    | wherever the pom's surefire `reportsDirectory` points; surefire has no command line override for it, so point it at `@CMAKE_BINARY_DIR@/junit/...` from `pom.xml.in`                                                                                                                                                                                            |

The per-test XML comes from properties of the tests themselves, so any ctest invocation produces it; only `junit/ctest.xml` depends on the `--output-junit` argument, which `make test`, the generated `test` target, and the Visual Studio `RUN_TESTS` target pass (`CMAKE_CTEST_ARGUMENTS`), and `cmake\test.cmd` does not.

## formatting

The build tree's `format` target rewrites in place every source the build knows how to format, and the root `make format` builds it. Providers register the way test providers register with ctest: a provider that can format a language creates its own target and calls `derammo_format_target(<target>)` (see `derammo_format.cmake`); the deferred finalize makes `format` depend on every registered target, and creates `format` even when nothing registered. `format` is the one reserved name; a project does not define its own. The providers so far: the C and C++ lint set through the `clang-format` target, when `.clang-format` is present and a matching tool was found (see code quality below), and every npm package through its `<prefix>_format` target, which runs the package's `format` script if it has one, from the workspace root for a workspace member so hoisted dependencies resolve.

`make format`, like `make npm-update`, runs in the build tree of `DERAMMO_TOOL_CONFIG`: the first of Release, Debug and RelWithDebInfo that is configured, or Debug when none is, configured first when it is missing or stale, so a switch file or a tool that appeared since the last configure is seen; set it as `make format DERAMMO_TOOL_CONFIG=Debug`.

### the format hook

The git pre-commit hook (see `scripts/format_all.sh`) runs the root `make format`, prints `[format hook] reformatted <path>` for every file a formatter rewrote, staged or not (a file that needed formatting was edited with the wrong settings somewhere), and re-stages the files that were fully staged, so the formatting lands in the commit; a partially staged file is left as staged and reported, since re-adding it would sweep its unstaged hunks into the commit. The rewritten files are found through git, as the files with an unstaged change after formatting that had none before, so the report is the same for every formatter. `make format`'s own output is shown only when it fails; then the hook prints `[format hook] formatting skipped: make format failed, see above` and the commit goes ahead; the lint tests are the gate. The hook is a frozen copy of the script, installed only if no `pre-commit` hook exists, so a project whose hook predates a change to the script must delete `pre-commit` in its hooks directory and rebuild; configure prints where the build will place it.

## code quality (C and C++)

Targets registered with `derammo_lint_target(<target>)` (the `library`, `static` and `executable` setup actions add the call) are compiled with strict warnings as errors, and their sources get one ctest per file and check, all labelled `lint`: `make lint` runs them, `make format` rewrites the files with clang-format. The checked files are the target's SOURCES, headers included, which the auto targets list by globbing and a hand-written target must list itself. A C or C++ file in the target's directory, `include/` or `src/` (`gtest/` for a test target) that no registered target lists is not checked; configure names such files in one status line, `lint: not sources of any registered target, so not checked:`, so that leaving one out is a decision.

Each lint test is one tool run on one file, so `make lint` runs them `DERAMMO_LINT_PARALLEL_LEVEL` at a time: 10, or the value set in the environment or as `make lint DERAMMO_LINT_PARALLEL_LEVEL=4`. The setting reaches no other ctest run: `make test` and `make test-lint` run the same tests one at a time, like every other test. A clang-tidy run can take a gigabyte of memory, which is the limit on small machines. `make lint DERAMMO_SKIP_BUILD=1` skips building Debug first; the tests read the sources and the compile database, so the tree is still configured when an input changed.

| test                 | passes when                                                                                                                                                | needs              |
|----------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------|
| `lint_format/<path>` | `clang-format --dry-run -Werror` finds nothing to change                                                                                                   | `.clang-format`    |
| `lint_tidy/<path>`   | `clang-tidy` reports nothing (`.c`, `.cc`, `.cpp`, `.cxx` sources only; headers are judged through the files that include them)                            | `.clang-tidy`      |
| `lint_size/<path>`   | the file has at most `DERAMMO_LINT_MAX_LINES` (a cache variable) lines of code (not blank, not starting with `//`; block comments count)                   | nothing, always on |

The size rule applies to production files only, not to files of `gtest/` targets. A file opts out with its first line, `// NOLINTFILE(max-lines): <reason>`; the reason is required, and the test prints it as `exempt: <reason>` so an exemption is never silent.

The strict flags are the `derammo::strict` target, linked privately: `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion -Wnull-dereference -Wimplicit-fallthrough -Wformat=2 -Werror`, plus `-Wold-style-cast -Wnon-virtual-dtor -Woverloaded-virtual` for C++; `/W4 /WX /permissive-` for MSVC and clang-cl. `-DDERAMMO_LINT_STRICT=OFF` leaves that target without flags, so a project can update this submodule first and clean up its warnings after; configure prints `strict: enabled` or `strict: disabled (DERAMMO_LINT_STRICT is off)`. Files below a directory named `thirdparty` get no tests, and a registered target's own `thirdparty/` directory is a SYSTEM include, so vendored headers do not trip the strict flags.

### switch files

The checks are switched on by tracked files at the source root, so that being on or off is visible in the repository. `setup.make` `library` and `executable` copy `setup_templates/clang-format.init` to `.clang-format` and `clang-tidy.init` to `.clang-tidy` at the project root (existing files are kept); delete one to turn its check off. The first line of each names the tool major it was written for, `# clang-format 21`, and only that major is ever used: another clang-format formats differently, another clang-tidy names its checks differently. The function complexity and length thresholds are the `CheckOptions` of `setup_templates/clang-tidy.init`, and of the project's `.clang-tidy` once copied. `setup_templates/gtest_clang-tidy.init` relaxes them for tests; `derammo_add_gtest_target` writes it to `gtest/.clang-tidy` at configure when that file is absent.

Configure prints one status line per check, e.g. `format: enabled`, `tidy: disabled (.clang-tidy absent)`, or `format: disabled (clang-format not found; make -C cmake/tools clang-format)`. A switch file that names no major, or a clang-tidy older than 19, also disables its check, and the Visual Studio and Xcode generators, which write no compile database, disable tidy. Apple numbers its clang independently of LLVM, so Xcode's tool matching the major is a coincidence; it is used, since it works on a plain macOS machine, with a status line saying its results may differ from the LLVM release. Configure reruns when a switch file or an installed tool appears, changes, or is deleted, through `make`; on Windows re-run `cmake\make.cmd`.

With `-DDERAMMO_LINT_REQUIRED=ON` a present switch file whose tool is missing or of another major fails configure instead of printing a disabled line, for CI.

### finding the tools

For the major named in the switch file, the first of these holding a matching version wins: `~/.local/bin` (`%LOCALAPPDATA%\derammo\bin` on Windows, where `make -C cmake/tools` installs), each `PATH` entry, Homebrew's LLVM (`/opt/homebrew/opt/llvm/bin`, `/usr/local/opt/llvm/bin`), and on macOS `xcrun --find`. Nothing is fetched automatically. To fetch LLVM's own release (21.1.8) by hand, from the project root:

```
make -C cmake/tools
make -C cmake/tools clang-format
make -C cmake/tools clang-tidy
```

`make -C cmake/tools` with no argument fetches both tools in one download; the named targets fetch one each (`cmake\tools\clang-format.cmd` and `clang-tidy.cmd` on Windows). Every run downloads the whole toolchain for the host and installs only the tools asked for, so it is a big download:

| host          | download |
|---------------|----------|
| macOS arm64   | 1.5 GB   |
| Linux x86_64  | 2.0 GB   |
| Linux aarch64 | 1.9 GB   |
| Windows x64   | 0.9 GB   |

The download is checked against the sha256 recorded in `tools/fetch_llvm_tool.cmake`, then its provenance: the GitHub build attestation with `gh attestation verify` (macOS, Linux), or the PGP signature with `gpg` against `tools/llvm-release-keys.asc` (Windows); without `gh` or `gpg` only the hash is checked, and the script says so. A failed check deletes the download. `clang-tidy` also installs clang's builtin headers into `~/.local/lib/clang/<major>/include`, which it needs to parse any source that includes a standard header; when that directory already exists the script stops before downloading, since it replaces nothing it did not just install, and says what to remove by hand; on Linux the shared libraries go to `~/.local/lib/derammo-llvm-<version>`, reached by an rpath when `patchelf` is found and otherwise by a wrapper script. `DERAMMO_LLVM_TMP` in the environment names the download directory.

LLVM publishes no macOS x86_64 binary for this release. There, the script stops with the commands to build from source instead: a 2 GB checkout, about 20 GB of disk, an hour or more on 8 cores.

## generating targets for subdirectories

To initialize a suitable config for a library/executable/etc, there are make targets to initialize cmake. For example, if you have a subdirectory "foo" that should be built as a library, you can

```
cd foo
make -f ../cmake/setup.make library
```

to create a pretty decent default configuration for a library in the current directory.

`cmake/setup.make` is always run from the directory being initialized, e.g. `make -f cmake/setup.make root` from the project root or `make -f ../cmake/setup.make executable` from a subfolder.

| target       | run from                                   | initializes                                                                                                                                                                  |
|--------------|--------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `root`       | project root containing the `cmake` folder | a new project root: `Makefile`, top-level `CMakeLists.txt` with `add_subdirectory()` entries and CPack support, and a `.gitignore` (merged with any existing one)            |
| `library`    | subfolder of the root                      | a shared library target: `CMakeLists.txt` plus `sources.cmake` listing local sources (PUBLIC), `include/` headers (INTERFACE), and `src/` files (PRIVATE)                    |
| `static`     | subfolder of the root                      | a static library target (runs `library` with `DERAMMO_LIBRARY_TYPE=STATIC`)                                                                                                  |
| `executable` | subfolder of the root                      | an executable target: `CMakeLists.txt` plus `sources.cmake` listing local sources (PUBLIC) and `src/` files (PRIVATE)                                                        |
| `workspaces` | subfolder of the root                      | an npm workspace root: `CMakeLists.txt`, `_package_template.json`, `templates/_package_template_version.json`, and `.gitignore`                                              |
| `typescript` | subfolder of an npm workspace root         | an npm package with TypeScript and vitest support: `CMakeLists.txt`, `_package_template.json`, `tsconfig.json`, `eslint.config.js`, `src/index.ts`, and `test/index.test.ts` |
| `npm`        | subfolder of an npm workspace root         | a plain npm package: `CMakeLists.txt` and `_package_template.json`                                                                                                           |

The npm-related targets (`workspaces`, `typescript`, `npm`) only create files that are not already present, so they can be run against an existing folder — except that they refuse to run if a `package.json` exists, since the build would replace it with a generated file. The remaining rules in `setup.make` (`Makefile`, `CMakeLists.txt`, `.gitignore`) are file rules used as prerequisites of `root`, not targets to invoke directly.

## examples

Example usage can be found at https://github.com/derammo/cmake_tests/tree/main/examples

For example, a simple library target with globbing (uses all files currently in the tree, instead of a list of source files) is shown here:
https://github.com/derammo/cmake_tests/blob/main/examples/autolib/CMakeLists.txt
