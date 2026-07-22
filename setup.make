# make file used to initialize directories with cmake support, to be run from those directories
#
# e.g. make -f cmake/setup.make root
# e.g. make -f ../cmake/setup.make executable

# initialize a new project to use this cmake system via a "cmake" folder in that project's root
root: Makefile CMakeLists.txt .gitignore

# location of this makefile's folder, so npm targets can be run from subdirectories at any depth
DERAMMO_SETUP_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

# default library type
DERAMMO_LIBRARY_TYPE=SHARED

# initialize a library target in a subfolder of the root
library: ../CMakeLists.txt
	PROJECT_NAME=$$(basename $$(pwd)) && \
	echo "add_library($${PROJECT_NAME} $(DERAMMO_LIBRARY_TYPE))" \
		> CMakeLists.txt && \
	echo "target_include_directories($${PROJECT_NAME} PUBLIC include)" \
		>> CMakeLists.txt && \
	echo "target_include_directories($${PROJECT_NAME} PRIVATE src)" \
		>> CMakeLists.txt && \
	echo "include(sources.cmake)" \
		>> CMakeLists.txt && \
	: > sources.cmake && \
	for local in *.cpp *.cxx *.cc *.c *.hpp *.hh *.h ; do \
		[ -f $${local} ] && echo "target_sources($${PROJECT_NAME} PUBLIC $${local})" >> sources.cmake || true ; \
	done ; \
	for interface in $$(find include -type f \( -name '*.h' -or -name '*.hh' -or -name '*.hpp' \)) ; do \
		[ -f $${interface} ] && echo "target_sources($${PROJECT_NAME} INTERFACE $${interface})" >> sources.cmake || true ; \
	done ; \
	for private in $$(find src -type f \( -name '*.cpp' -or -name '*.cxx' -or -name '*.cc' -or -name '*.c' -or -name '*.hpp' -or -name '*.hh' -or -name '*.h' \)) ; do \
		[ -f $${private} ] && echo "target_sources($${PROJECT_NAME} PRIVATE $${private})" >> sources.cmake || true ; \
	done

# refuse to set up npm support on top of an existing package.json, since the build
# will replace it with a generated file
define DERAMMO_NPM_GUARD
	@if [ -f package.json ] ; then \
		echo "ERROR: package.json already exists in $$(pwd)" ; \
		echo "this setup action will replace package.json with one generated from templates" ; \
		echo "manually rename it (to keep it for reference) or delete it before running this command" ; \
		false ; \
	fi
endef

# initialize an npm workspace root in a subfolder of the root
# all files are only created if not already present, so this can be run against an existing folder
workspaces: ../CMakeLists.txt
	$(DERAMMO_NPM_GUARD)
	[ -f CMakeLists.txt ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_workspaces_CMakeLists.init CMakeLists.txt
	[ -f _package_template.json ] || { \
		PROJECT_NAME=$$(basename $$(pwd)) && \
		sed -e s/REPLACE_PROJECT_NAME/$${PROJECT_NAME}/g \
			< $(DERAMMO_SETUP_DIR)setup_templates/npm_workspaces_package_template.init \
			> _package_template.json ; }
	mkdir -p templates
	[ -f templates/_package_template_version.json ] || \
		cp $(DERAMMO_SETUP_DIR)npm_package_templates/_package_template_version.json templates/
	[ -f .gitignore ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_gitignore.init .gitignore

# initialize an npm package with typescript and vitest support in a subfolder of a workspace root
# all files are only created if not already present, so this can be run against an existing package
typescript: ../CMakeLists.txt
	$(DERAMMO_NPM_GUARD)
	[ -f CMakeLists.txt ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_package_CMakeLists.init CMakeLists.txt
	[ -f _package_template.json ] || { \
		PROJECT_NAME=$$(basename $$(pwd)) && \
		WORKSPACE_NAME=$$(basename $$(dirname $$(pwd))) && \
		sed -e s/REPLACE_PROJECT_NAME/$${PROJECT_NAME}/g \
			-e s/REPLACE_WORKSPACE_NAME/$${WORKSPACE_NAME}/g \
			< $(DERAMMO_SETUP_DIR)setup_templates/npm_typescript_package_template.init \
			> _package_template.json ; }
	[ -f tsconfig.json ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_tsconfig.init tsconfig.json
	[ -f eslint.config.js ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_eslint_config.init eslint.config.js
	mkdir -p src test
	[ -f src/index.ts ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_index_ts.init src/index.ts
	[ -f test/index.test.ts ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_index_test_ts.init test/index.test.ts

# initialize an npm package without anything special in a subfolder of a workspace root
# all files are only created if not already present, so this can be run against an existing package
npm: ../CMakeLists.txt
	$(DERAMMO_NPM_GUARD)
	[ -f CMakeLists.txt ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_package_CMakeLists.init CMakeLists.txt
	[ -f _package_template.json ] || { \
		PROJECT_NAME=$$(basename $$(pwd)) && \
		WORKSPACE_NAME=$$(basename $$(dirname $$(pwd))) && \
		sed -e s/REPLACE_PROJECT_NAME/$${PROJECT_NAME}/g \
			-e s/REPLACE_WORKSPACE_NAME/$${WORKSPACE_NAME}/g \
			< $(DERAMMO_SETUP_DIR)setup_templates/npm_plain_package_template.init \
			> _package_template.json ; }

# initialize a static library target in a subfolder of the root
static:
	${MAKE} -f ../cmake/setup.make DERAMMO_LIBRARY_TYPE=STATIC library

# initialize an executable target in a subfolder of the root
executable: ../CMakeLists.txt
	PROJECT_NAME=$$(basename $$(pwd)) && \
	echo "add_executable($${PROJECT_NAME})" \
		> CMakeLists.txt && \
	echo "target_include_directories($${PROJECT_NAME} PRIVATE include)" \
		>> CMakeLists.txt && \
	echo "include(sources.cmake)" \
		>> CMakeLists.txt && \
	: > sources.cmake && \
	for local in *.cpp *.cxx *.cc *.c *.hpp *.hh *.h ; do \
		[ -f $${local} ] && echo "target_sources($${PROJECT_NAME} PUBLIC $${local})" >> sources.cmake || true ; \
	done ; \
	for private in $$(find src -type f \( -name '*.cpp' -or -name '*.cxx' -or -name '*.cc' -or -name '*.c' -or -name '*.hpp' -or -name '*.hh' -or -name '*.h' \)) ; do \
		[ -f $${private} ] && echo "target_sources($${PROJECT_NAME} PRIVATE $${private})" >> sources.cmake || true ; \
	done

Makefile: | cmake/setup_templates/Makefile.init
	cp cmake/setup_templates/Makefile.init $@

CMakeLists.txt: | cmake/setup_templates/CMakeLists.init
	PROJECT_NAME=$$(basename $$(pwd)) && \
	sed -e s/REPLACE_PROJECT_NAME/$${PROJECT_NAME}/g < cmake/setup_templates/CMakeLists.init > $@

	# create initial list of subdirectories by exclusion of known names
	PROJECTS="$$(find . -maxdepth 1 \
		-name "$(strip $(DERAMMO_PLATFORM))" -prune -or \
		-name "Windows" -prune -or \
		-name "cmake" -prune -or \
		-name "build" -prune -or \
		-name "bin" -prune -or \
		-name "lib" -prune -or \
		-name "include" -prune -or \
		-name ".git" -prune -or \
		-name "." -or \
		-type d -print )" && \
	echo $$PROJECTS && \
	for project in $$PROJECTS ; \
		do \
		echo "add_subdirectory($$(basename $${project}))" >> $@ ;\
	done 
	echo >> $@
	echo "# packaging support" >> $@
	echo "include(CPack)" >> $@

# default gitignore file
.gitignore: | cmake/setup_templates/gitignore.init
	# may duplicate things, but that is the safer choice than overwriting
	@if [ -f .gitignore ] ; then \
		echo merging gitignore files ; \
		cp .gitignore .gitignore.old ; \
		cat .gitignore.old cmake/setup_templates/gitignore.init | sort -u > .gitignore ; \
	else \
		echo creating gitignore file ; \
		cp cmake/setup_templates/gitignore.init .gitignore ; \
	fi
	