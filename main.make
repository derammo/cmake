# make file for all platforms that are posix-like (i.e. not windows native via Visual Studio, run make.cmd for that platform)
#
# to be included from the root level Makefile of a project (automatically done if cmake/setup.make is used to initialize the root)

# the generated build system is several levels of sub-make in one directory,
# which would otherwise announce that directory on every entry and exit;
# MAKEFLAGS is inherited by every sub-make, so this silences all of them
MAKEFLAGS += --no-print-directory

# inventory
DERAMMO_PLATFORM := $(strip $(shell uname -s))
DERAMMO_CMAKE_LISTS := $(shell find . -name "CMakeLists.txt") cmake/main.make
DERAMMO_CMAKE_SOURCES := $(wildcard cmake/derammo*.cmake)

.PHONY: all clean squeaky configure release package docker relWithDebInfo debug probe info test trace
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
	rm -rf Windows
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

# every test provider registers with ctest under a label naming the provider
# (gtest, npm, vitest, jest, maven, ...), so this runs all of them; JUnit XML
# for each test and for the run as a whole lands in the junit folder of the
# build directory, matching CMAKE_CTEST_ARGUMENTS in derammo_main.cmake
test: debug
	cd $(DERAMMO_PLATFORM)/Debug && ctest --output-on-failure --output-junit junit/ctest.xml

# run only the tests of one provider, e.g. `make test-npm`; `ctest --print-labels`
# in the build directory lists what is registered
test-%: debug
	cd $(DERAMMO_PLATFORM)/Debug && ctest --output-on-failure --output-junit junit/ctest.xml -L $*

# XXX: testRelease

# XXX: if we don't use gtest, how will this tie into release builds?

# generate required folders
$(DERAMMO_PLATFORM)/Release:
	mkdir -p $@
$(DERAMMO_PLATFORM)/Debug:
	mkdir -p $@
$(DERAMMO_PLATFORM)/RelWithDebInfo:
	mkdir -p $@

# recompile cmake if necessary
$(DERAMMO_PLATFORM)/%/Makefile: $(DERAMMO_CMAKE_SOURCES) $(DERAMMO_CMAKE_LISTS) Makefile
	# on platforms where we use make to update the cmake files, we only support g++/gcc as compilers
	# which is aliased on Darwin to use the preferred compiler there also
	cmake -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -S . -B $(DERAMMO_PLATFORM)/$* -DCMAKE_BUILD_TYPE=$* -DDERAMMO_RELATIVE_BINARY_DIR=$(DERAMMO_PLATFORM)/$*

# compile cmake for debug tracing of CMake operation
trace: $(DERAMMO_CMAKE_SOURCES) $(DERAMMO_CMAKE_LISTS) Makefile
	cmake --trace -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -S . -B $(DERAMMO_PLATFORM)/Debug -DCMAKE_BUILD_TYPE=Debug -DDERAMMO_RELATIVE_BINARY_DIR=$(DERAMMO_PLATFORM)/Debug
