# make file for all platforms that are posix-like (i.e. not windows native via Visual Studio, run make.cmd for that platform)
#
# to be included from the root level Makefile of a project (automatically done if cmake/setup.make is used to initialize the root)

# inventory
DERAMMO_PLATFORM := $(strip $(shell uname -s))
DERAMMO_CMAKE_LISTS := $(shell find . -name "CMakeLists.txt") cmake/main.make
DERAMMO_CMAKE_SOURCES := $(wildcard cmake/derammo*.cmake)

.PHONY: all clean squeaky release package docker relWithDebInfo debug probe info test gtest mtest trace
all: release $(DERAMMO_ALL_TARGETS)

clean: 
	if [ -d $$(/usr/bin/uname -s)/Release ] ; then cd $$(/usr/bin/uname -s)/Release && make clean ; fi
	if [ -d $$(/usr/bin/uname -s)/RelWithDebInfo ] ; then cd $$(/usr/bin/uname -s)/RelWithDebInfo && make clean ; fi
	if [ -d $$(/usr/bin/uname -s)/Debug ] ; then cd $$(/usr/bin/uname -s)/Debug && make clean ; fi

squeaky: $(DERAMMO_SQUEAKY_TARGETS)
	rm -rf $(DERAMMO_PLATFORM)
	rm -rf Windows
	
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

# REVISIT: also execute other supported test types
test: gtest mtest
gtest: debug
	if [ -d $(DERAMMO_PLATFORM)/Debug ] ; then cd $(DERAMMO_PLATFORM)/Debug && ctest --output-on-failure ; fi
mtest: debug 
	# run maven tests
	if [ -f pom.xml ] ; then mvn test ; fi

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
