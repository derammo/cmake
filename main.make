# make file for all platforms that are posix-like (i.e. not windows native via Visual Studio, run make.cmd for that platform)
#
# to be included from the root level Makefile of a project (automatically done if cmake/setup.make is used to initialize the root)

# inventory
DERAMMO_PLATFORM := $(shell uname -s) 
DERAMMO_CMAKE_LISTS := $(shell find -name "CMakeLists.txt") cmake/main.make
DERAMMO_CMAKE_SOURCES := $(wildcard cmake/derammo*.cmake)

all: release $(DERAMMO_ALL_TARGETS)

clean: 
	if [ -d $$(/usr/bin/uname -s)/Release ] ; then cd $$(/usr/bin/uname -s)/Release && make clean ; fi
	if [ -d $$(/usr/bin/uname -s)/RelWithDebInfo ] ; then cd $$(/usr/bin/uname -s)/RelWithDebInfo && make clean ; fi
	if [ -d $$(/usr/bin/uname -s)/Debug ] ; then cd $$(/usr/bin/uname -s)/Debug && make clean ; fi

squeaky: $(DERAMMO_SQUEAKY_TARGETS)
	rm -rf $(strip $(DERAMMO_PLATFORM))
	rm -rf Windows
	
release: $(strip $(DERAMMO_PLATFORM))/Release $(strip $(DERAMMO_PLATFORM))/Release/Makefile
	cd $< && make

package: $(strip $(DERAMMO_PLATFORM))/Release $(strip $(DERAMMO_PLATFORM))/Release/Makefile
	cd $< && make package

docker: $(strip $(DERAMMO_PLATFORM))/Release $(strip $(DERAMMO_PLATFORM))/Release/Makefile
	cd $< && make docker

relWithDebInfo: $(strip $(DERAMMO_PLATFORM))/RelWithDebInfo $(strip $(DERAMMO_PLATFORM))/RelWithDebInfo/Makefile
	cd $< && make

debug: $(strip $(DERAMMO_PLATFORM))/Debug $(strip $(DERAMMO_PLATFORM))/Debug/Makefile
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
    # REVISIT: decide if we want to use CTest or something else instead of this trivial runner
	cd Linux/Debug/runtime && for tester in ../bin/*_gtest ; do $${tester} ; done
mtest: debug 
	# run maven tests
	mvn test

# XXX: testRelease

# XXX: if we don't use gtest, how will this tie into release builds?

# generate required folders
$(strip $(DERAMMO_PLATFORM))/%:
	mkdir -p $@

# recompile cmake if necessary
$(strip $(DERAMMO_PLATFORM))/%/Makefile: $(DERAMMO_CMAKE_SOURCES) $(DERAMMO_CMAKE_LISTS) Makefile
	cmake -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ -S . -B $(strip $(DERAMMO_PLATFORM))/$* -DCMAKE_BUILD_TYPE=$* -DDERAMMO_RELATIVE_BINARY_DIR=$(strip $(DERAMMO_PLATFORM))/$*
