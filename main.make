# make file for all platforms that are posix-like (i.e. not windows native via Visual Studio, run make.cmd for that platform)
#
# to be included from the root level Makefile of a project (automatically done if cmake/setup.make is used to initialize the root)

# the generated build system is several levels of sub-make in one directory,
# which would otherwise announce that directory on every entry and exit;
# MAKEFLAGS is inherited by every sub-make, so this silences all of them
MAKEFLAGS += --no-print-directory

# `make QUICK=1` skips npm package builds whose recorded inputs are unchanged
# (see derammo_npm.cmake); the build commands read QUICK from the
# environment, which `QUICK=1 make` reaches on its own, so exporting makes
# the command line form equivalent
export QUICK

# inventory
DERAMMO_PLATFORM := $(strip $(shell uname -s))
DERAMMO_CMAKE_LISTS := $(shell find . -name "CMakeLists.txt") cmake/main.make
DERAMMO_CMAKE_SOURCES := $(wildcard cmake/derammo*.cmake)

# the switch files and fetched tools that turn the C++ lint on; wildcard is
# evaluated at make time, so one that is absent drops out of the list instead of
# being a missing prerequisite, and one that newly appears re-runs configure
# (a switch file that exists is also a CMAKE_CONFIGURE_DEPENDS of the project,
# which covers editing or deleting it)
DERAMMO_LINT_INPUTS := $(wildcard .clang-format .clang-tidy $(HOME)/.local/bin/clang-format $(HOME)/.local/bin/clang-tidy)

# how many lint tests ctest runs at once under `make lint`; each lint test is
# one tool run on one file with no shared state, so any level is safe, and
# this reaches no other ctest invocation, whose tests keep running one at a
# time; set in the environment or as `make lint DERAMMO_LINT_PARALLEL_LEVEL=4`;
# a clang-tidy run can take a gigabyte, which is the limit on small machines
DERAMMO_LINT_PARALLEL_LEVEL ?= 10

# `make lint DERAMMO_SKIP_BUILD=1` runs the lint tests without building Debug
# first; the tests read sources and the compile database, so the tree is still
# configured, which does nothing when no input changed
ifneq ($(DERAMMO_SKIP_BUILD),)
DERAMMO_LINT_PREREQUISITES := $(DERAMMO_PLATFORM)/Debug $(DERAMMO_PLATFORM)/Debug/Makefile
else
DERAMMO_LINT_PREREQUISITES := debug
endif

.PHONY: all clean squeaky configure release package docker relWithDebInfo debug probe info test trace lint format npm-update npm-outdated test-report.txt
all: release $(DERAMMO_ALL_TARGETS)

clean: 
	if [ -d $$(/usr/bin/uname -s)/Release ] ; then cd $$(/usr/bin/uname -s)/Release && make clean ; fi
	if [ -d $$(/usr/bin/uname -s)/RelWithDebInfo ] ; then cd $$(/usr/bin/uname -s)/RelWithDebInfo && make clean ; fi
	if [ -d $$(/usr/bin/uname -s)/Debug ] ; then cd $$(/usr/bin/uname -s)/Debug && make clean ; fi

# npm folders below the root are removed by the clean target, which visits exactly
# the directories that declared npm support; other npm packages in the same source
# tree are not ours to touch
squeaky: clean $(DERAMMO_SQUEAKY_TARGETS)
	rm -rf $(DERAMMO_PLATFORM)
	if [ -L build ] ; then rm build ; fi
	rm -rf node_modules cmake/scripts/node_modules

configure: $(DERAMMO_PLATFORM)/Release \
	$(DERAMMO_PLATFORM)/Release/Makefile \
	$(DERAMMO_PLATFORM)/Debug \
	$(DERAMMO_PLATFORM)/Debug/Makefile \
	$(DERAMMO_PLATFORM)/RelWithDebInfo \
	$(DERAMMO_PLATFORM)/RelWithDebInfo/Makefile

release: $(DERAMMO_PLATFORM)/Release $(DERAMMO_PLATFORM)/Release/Makefile
	cd $< && make

package: $(DERAMMO_PLATFORM)/Release $(DERAMMO_PLATFORM)/Release/Makefile
	cd $< && make package

docker: $(DERAMMO_PLATFORM)/Release $(DERAMMO_PLATFORM)/Release/Makefile
	cd $< && make docker || true

relWithDebInfo: $(DERAMMO_PLATFORM)/RelWithDebInfo $(DERAMMO_PLATFORM)/RelWithDebInfo/Makefile
	cd $< && make

debug: $(DERAMMO_PLATFORM)/Debug $(DERAMMO_PLATFORM)/Debug/Makefile
	cd $< && make

probe: ${DERAMMO_PLATFORM}
	@echo $<

info:
	@echo $(DERAMMO_PLATFORM)
	@echo $(DERAMMO_CMAKE_LISTS)
	@echo $(DERAMMO_CMAKE_SOURCES)
	@echo $(DERAMMO_LINT_INPUTS)

# how ctest reports: the output of a failed test is shown, and JUnit XML for
# each test and for the run as a whole lands in the junit folder of the build
# directory, matching CMAKE_CTEST_ARGUMENTS in derammo_main.cmake
DERAMMO_CTEST_REPORT := --output-on-failure --output-junit junit/ctest.xml

# a report run of the tests records the state of one commit: it starts from
# an empty junit folder, keeps a copy of the JUnit XML without the output
# that is not worth keeping under the commit hash, outside git and outside
# the build directory, and writes one line per test to the report at the
# source root (see scripts/junit_report.ts)
DERAMMO_JUNIT_DIR := $(DERAMMO_PLATFORM)/Debug/junit
DERAMMO_TEST_REPORT := test-report.txt
DERAMMO_TEST_HISTORY := .derammo/test-history/$(DERAMMO_PLATFORM)

# true when nothing here or in a submodule is uncommitted or untracked; a
# folder that git does not manage is never clean
DERAMMO_TREE_IS_CLEAN = { derammo_changes=$$(git status --porcelain 2>/dev/null) && [ -z "$$derammo_changes" ]; }

# runs the tests and exits with the status of ctest; with the shell variable
# derammo_report set, as a report run
define DERAMMO_RUN_TESTS
if [ -n "$$derammo_report" ]; then rm -rf $(DERAMMO_JUNIT_DIR) && mkdir -p $(DERAMMO_JUNIT_DIR) || exit; fi; \
( cd $(DERAMMO_PLATFORM)/Debug && ctest $(DERAMMO_CTEST_REPORT) ); derammo_status=$$?; \
if [ -n "$$derammo_report" ]; then \
	node cmake/scripts/junit_report.ts $(DERAMMO_JUNIT_DIR) $(DERAMMO_TEST_HISTORY)/$$(git rev-parse HEAD) $(DERAMMO_TEST_REPORT) || exit; \
	echo "$(DERAMMO_TEST_REPORT) written for $$(git rev-parse --short HEAD)"; \
fi; \
exit $$derammo_status
endef

# every test provider registers with ctest under a label naming the provider
# (gtest, npm, vitest, jest, maven, ...), so this runs all of them; when the
# tree is clean before the build and still clean after it, and node is there
# to write the report, this is a report run
test:
	@if $(DERAMMO_TREE_IS_CLEAN) && command -v node >/dev/null; then derammo_report=1; else derammo_report=; fi; \
	$(MAKE) debug || exit; \
	if [ -n "$$derammo_report" ] && ! $(DERAMMO_TREE_IS_CLEAN); then derammo_report=; fi; \
	$(DERAMMO_RUN_TESTS)

# the report run on its own: fails without running a test when the tree is
# not clean, or when the build leaves it not clean
$(DERAMMO_TEST_REPORT):
	@if ! $(DERAMMO_TREE_IS_CLEAN); then \
		echo "$@: uncommitted changes, commit them first:" >&2; git status --short >&2; exit 1; \
	fi; \
	$(MAKE) debug || exit; \
	if ! $(DERAMMO_TREE_IS_CLEAN); then \
		echo "$@: the build changed these, commit them and run again:" >&2; git status --short >&2; exit 1; \
	fi; \
	derammo_report=1; \
	$(DERAMMO_RUN_TESTS)

# run only the tests of one provider, e.g. `make test-npm`; `ctest --print-labels`
# in the build directory lists what is registered
test-%: debug
	cd $(DERAMMO_PLATFORM)/Debug && ctest $(DERAMMO_CTEST_REPORT) -L $*

# the C++ lint checks (format conformance, clang-tidy, file length) are ctests
# labelled lint; the same tests as `make test-lint`, run DERAMMO_LINT_PARALLEL_LEVEL
# at a time, after building Debug unless DERAMMO_SKIP_BUILD is set
lint: $(DERAMMO_LINT_PREREQUISITES)
	cd $(DERAMMO_PLATFORM)/Debug && ctest $(DERAMMO_CTEST_REPORT) -L lint -j $(DERAMMO_LINT_PARALLEL_LEVEL)

# the configuration whose build tree the tool targets (format, npm-update)
# run in: the first of Release, Debug and RelWithDebInfo that is configured,
# so a tool never configures a second tree, and Debug when none is; what the
# tools act on is the same in every configuration; set as
# `make format DERAMMO_TOOL_CONFIG=Debug`
DERAMMO_TOOL_CONFIG ?= $(firstword $(patsubst $(DERAMMO_PLATFORM)/%/Makefile,%,$(wildcard $(DERAMMO_PLATFORM)/Release/Makefile $(DERAMMO_PLATFORM)/Debug/Makefile $(DERAMMO_PLATFORM)/RelWithDebInfo/Makefile)) Debug)

# rewrite the sources in place with every formatter the build registered
# (clang-format for the C and C++ lint set when .clang-format is present and
# a matching tool was found, the format script of every npm package, ...),
# through the build tree of DERAMMO_TOOL_CONFIG, configured first when it
# is missing or stale (a switch file or a tool that appeared since makes it
# stale); see derammo_format.cmake for how a provider registers
format: $(DERAMMO_PLATFORM)/$(DERAMMO_TOOL_CONFIG) $(DERAMMO_PLATFORM)/$(DERAMMO_TOOL_CONFIG)/Makefile
	cd $(DERAMMO_PLATFORM)/$(DERAMMO_TOOL_CONFIG) && make format

# move every npm dependency to the newest version its range allows, in every
# npm root the build knows: each workspace root with its members, and each
# package outside a workspace; an install never does this on its own, it keeps
# what the lock file records; npm-outdated prints what npm-update would change
# and changes nothing
#
# the build tree targets these call exist only when the project includes the
# optional npm module (derammo_npm.cmake); without it, the build tree's make
# reports that it has no rule to make the target, and nothing runs
npm-update: $(DERAMMO_PLATFORM)/$(DERAMMO_TOOL_CONFIG) $(DERAMMO_PLATFORM)/$(DERAMMO_TOOL_CONFIG)/Makefile
	cd $(DERAMMO_PLATFORM)/$(DERAMMO_TOOL_CONFIG) && make npm_update
npm-outdated: $(DERAMMO_PLATFORM)/$(DERAMMO_TOOL_CONFIG) $(DERAMMO_PLATFORM)/$(DERAMMO_TOOL_CONFIG)/Makefile
	cd $(DERAMMO_PLATFORM)/$(DERAMMO_TOOL_CONFIG) && make npm_outdated

# XXX: testRelease

# XXX: if we don't use gtest, how will this tie into release builds?

# generate required folders
$(DERAMMO_PLATFORM)/Release:
	mkdir -p $@
$(DERAMMO_PLATFORM)/Debug:
	mkdir -p $@
$(DERAMMO_PLATFORM)/RelWithDebInfo:
	mkdir -p $@

# the platform's build trees under a name that does not depend on the platform,
# so that editor settings can name a path such as
# build/Debug/compile_commands.json; a project that has a file or directory of
# its own called build keeps it, since the rule only runs when nothing is there
build:
	ln -sfn $(DERAMMO_PLATFORM) $@

# recompile cmake if necessary; the link is an order-only prerequisite, so it
# is made when missing but never causes a configure
$(DERAMMO_PLATFORM)/%/Makefile: $(DERAMMO_CMAKE_SOURCES) $(DERAMMO_CMAKE_LISTS) $(DERAMMO_LINT_INPUTS) Makefile | build
	# on platforms where we use make to update the cmake files, we only support g++/gcc as compilers
	# which is aliased on Darwin to use the preferred compiler there also
	cmake -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -S . -B $(DERAMMO_PLATFORM)/$* -DCMAKE_BUILD_TYPE=$* -DDERAMMO_RELATIVE_BINARY_DIR=$(DERAMMO_PLATFORM)/$*

# compile cmake for debug tracing of CMake operation
trace: $(DERAMMO_CMAKE_SOURCES) $(DERAMMO_CMAKE_LISTS) $(DERAMMO_LINT_INPUTS) Makefile
	cmake --trace -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -S . -B $(DERAMMO_PLATFORM)/Debug -DCMAKE_BUILD_TYPE=Debug -DDERAMMO_RELATIVE_BINARY_DIR=$(DERAMMO_PLATFORM)/Debug
