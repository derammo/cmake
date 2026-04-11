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

| target          | what it does                                                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `all` (default) | same as `release`                                                                                                               |
| `release`       | configure and build `<Platform>/Release` (e.g. `Linux/Release`, `Darwin/Release`)                                               |
| `debug`         | configure and build `<Platform>/Debug`                                                                                          |
| `relWithDebInfo`| configure and build `<Platform>/RelWithDebInfo`                                                                                 |
| `package`       | build Release, then run CPack (`make package`) in the Release build dir                                                         |
| `docker`        | build Release, then run the `docker` custom target if the project defines one (non-fatal if missing)                            |
| `test`          | build Debug, then run `gtest` and `mtest` (see below)                                                                           |
| `gtest`         | build Debug, then `ctest --output-on-failure` in the Debug build dir                                                            |
| `mtest`         | build Debug, then `mvn test` if the project has a `pom.xml` (no-op otherwise)                                                   |
| `clean`         | run `make clean` inside any existing `<Platform>/{Release,RelWithDebInfo,Debug}` build dir (keeps the dirs themselves)          |
| `squeaky`       | delete `<Platform>/` and `Windows/` entirely, removing all build artifacts                                                      |
| `info`          | print the detected platform and the inputs main.make watches for regeneration                                                  |
| `probe`         | print just the detected platform                                                                                                |
| `trace`         | re-run cmake with `--trace` into `<Platform>/Debug` for debugging CMake logic                                                   |

`<Platform>` is the output of `uname -s` (`Linux`, `Darwin`, etc.), so build trees for multiple platforms can coexist in the same source tree.

Several of the per-platform paths can also be invoked directly:

```
make Linux/Release
make Linux/Debug
make Darwin/Debug
```

## Windows (native, via Visual Studio)

Windows does not use `make` — the equivalents live in the `cmake\` submodule and are run from the project root:

| command              | equivalent POSIX target | what it does                                                          |
| -------------------- | ----------------------- | --------------------------------------------------------------------- |
| `cmake\make.cmd`     | `make` (all configs)    | generate `Windows\` build tree via `cmake -B Windows -A x64`          |
| `cmake\open.cmd`     | —                       | run `cmake\make.cmd` then open every generated `.sln` in Visual Studio |
| `cmake\test.cmd`     | `make test`             | run `ctest --output-on-failure` inside the `Windows\` build tree      |

In particular, **there is no `make test` on Windows** — use `cmake\test.cmd` instead.

## generating targets for subdirectories

To initialize a suitable config for a library/executable/etc, there are make targets to initialize cmake.  For example, if you have a subdirectory "foo" that should be built as a library, you can

```
cd foo
make -f ../cmake/setup.make library
```

to create a pretty decent default configuration for a library in the current directory.  Similar targets exist for executables and other typical uses for a subdirectory.

## examples

Example usage can be found at https://github.com/derammo/cmake_tests/tree/main/examples

For example, a simple library target with globbing (uses all files currently in the tree, instead of a list of source files) is shown here:
https://github.com/derammo/cmake_tests/blob/main/examples/autolib/CMakeLists.txt
