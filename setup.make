# make file used to initialize directories with cmake support, to be run from those directories
#
# e.g. make -f cmake/setup.make root
# e.g. make -f ../cmake/setup.make executable

# initialize a new project to use this cmake system via a "cmake" folder in that project's root
root: Makefile CMakeLists.txt .gitignore

# location of this makefile's folder, so npm targets can be run from subdirectories at any depth
DERAMMO_SETUP_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

# what the build will configure as CMAKE_SOURCE_DIR: the parent of this
# submodule, at whatever depth the target being initialized is
DERAMMO_SOURCE_DIR := $(DERAMMO_SETUP_DIR)../

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
	echo "derammo_lint_target($${PROJECT_NAME})" \
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
	[ -f $(DERAMMO_SOURCE_DIR).clang-format ] || cp $(DERAMMO_SETUP_DIR)setup_templates/clang-format.init $(DERAMMO_SOURCE_DIR).clang-format
	[ -f $(DERAMMO_SOURCE_DIR).clang-tidy ] || cp $(DERAMMO_SETUP_DIR)setup_templates/clang-tidy.init $(DERAMMO_SOURCE_DIR).clang-tidy

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

# initialize an npm workspace root in the root or a subfolder of the root
# all files are only created if not already present, so this can be run against an existing folder
workspaces:
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

# the scope for a new package's name comes from the name declared in the enclosing
# workspace's _package_template.json (e.g. "@foo/packages" scopes new packages as
# "@foo/..."); the workspace folder's basename is only the fallback
define DERAMMO_NPM_SCOPE
	WORKSPACE_SCOPE=$$(node -p 'String(JSON.parse(require("fs").readFileSync("../_package_template.json", "utf8")).name || "").split("/")[0]' 2>/dev/null || true) ; \
	[ -n "$$WORKSPACE_SCOPE" ] || WORKSPACE_SCOPE=$$(basename $$(dirname $$(pwd))) ; \
	case "$$WORKSPACE_SCOPE" in @*) ;; *) WORKSPACE_SCOPE="@$$WORKSPACE_SCOPE" ;; esac
endef

# initialize an npm package with typescript and vitest support in a subfolder of a workspace root
# all files are only created if not already present, so this can be run against an existing package
typescript: ../CMakeLists.txt
	$(DERAMMO_NPM_GUARD)
	[ -f CMakeLists.txt ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_package_CMakeLists.init CMakeLists.txt
	[ -f _package_template.json ] || { \
		PROJECT_NAME=$$(basename $$(pwd)) ; \
		$(DERAMMO_NPM_SCOPE) ; \
		sed -e s/REPLACE_PROJECT_NAME/$${PROJECT_NAME}/g \
			-e "s,REPLACE_SCOPE,$$WORKSPACE_SCOPE,g" \
			< $(DERAMMO_SETUP_DIR)setup_templates/npm_typescript_package_template.init \
			> _package_template.json ; }
	[ -f tsconfig.json ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_tsconfig.init tsconfig.json
	[ -f tsconfig.build.json ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_tsconfig_build.init tsconfig.build.json
	[ -f vitest.config.ts ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_vitest_config.init vitest.config.ts
	[ -f ../tsconfig.base.json ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_tsconfig_base.init ../tsconfig.base.json
	[ -f eslint.config.*js ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_eslint_config.init eslint.config.mjs
	mkdir -p test
	# install dummy files only in a new project
	[ -d src ] || ( mkdir src && cp $(DERAMMO_SETUP_DIR)setup_templates/npm_index_ts.init src/index.ts && cp $(DERAMMO_SETUP_DIR)setup_templates/npm_index_test_ts.init test/index.test.ts )

# initialize an npm package without anything special in a subfolder of a workspace root
# all files are only created if not already present, so this can be run against an existing package
npm: ../CMakeLists.txt
	$(DERAMMO_NPM_GUARD)
	[ -f CMakeLists.txt ] || cp $(DERAMMO_SETUP_DIR)setup_templates/npm_package_CMakeLists.init CMakeLists.txt
	[ -f _package_template.json ] || { \
		PROJECT_NAME=$$(basename $$(pwd)) ; \
		$(DERAMMO_NPM_SCOPE) ; \
		sed -e s/REPLACE_PROJECT_NAME/$${PROJECT_NAME}/g \
			-e "s,REPLACE_SCOPE,$$WORKSPACE_SCOPE,g" \
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
	echo "derammo_lint_target($${PROJECT_NAME})" \
		>> CMakeLists.txt && \
	: > sources.cmake && \
	for local in *.cpp *.cxx *.cc *.c *.hpp *.hh *.h ; do \
		[ -f $${local} ] && echo "target_sources($${PROJECT_NAME} PUBLIC $${local})" >> sources.cmake || true ; \
	done ; \
	for private in $$(find src -type f \( -name '*.cpp' -or -name '*.cxx' -or -name '*.cc' -or -name '*.c' -or -name '*.hpp' -or -name '*.hh' -or -name '*.h' \)) ; do \
		[ -f $${private} ] && echo "target_sources($${PROJECT_NAME} PRIVATE $${private})" >> sources.cmake || true ; \
	done
	[ -f $(DERAMMO_SOURCE_DIR).clang-format ] || cp $(DERAMMO_SETUP_DIR)setup_templates/clang-format.init $(DERAMMO_SOURCE_DIR).clang-format
	[ -f $(DERAMMO_SOURCE_DIR).clang-tidy ] || cp $(DERAMMO_SETUP_DIR)setup_templates/clang-tidy.init $(DERAMMO_SOURCE_DIR).clang-tidy

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

# set up the folder where agents are started, which may be the cmake root or
# any folder that the cmake root is reached from, e.g.
#   make -f cmake/setup.make agentroot
#   make -f some/project/cmake/setup.make agentroot
# for each agent that is supported (Claude Code), the agent is told where the
# cmake root is and given the instructions of the modules found there, by
# reference, so they change with the modules
agentroot: .claude/rules/derammo-cmake.md

# the cmake root as it is reached from the folder being set up: the folder
# this makefile's folder is in, ending in a slash, or nothing when that is
# the folder being set up itself
DERAMMO_AGENT_CMAKE_ROOT := $(patsubst ./%,%,$(dir $(patsubst %/,%,$(DERAMMO_SETUP_DIR))))

# what the agent is told about where the cmake root is
ifeq ($(DERAMMO_AGENT_CMAKE_ROOT),)
DERAMMO_AGENT_CMAKE_ROOT_SENTENCE := The cmake root for this project is the project root itself, i.e. the folder containing this `.claude` folder.
else
DERAMMO_AGENT_CMAKE_ROOT_SENTENCE := The cmake root for this project is `$(DERAMMO_AGENT_CMAKE_ROOT)`, relative to the folder containing this `.claude` folder.
endif

# a rule file is read from .claude/rules, two folders below the agent root
.claude/rules/derammo-cmake.md:
	@case "$(DERAMMO_SETUP_DIR)" in /*) \
		echo "agentroot: name setup.make by its path relative to this folder, as in make -f some/project/cmake/setup.make agentroot" >&2 ; \
		exit 1 ;; \
	esac
	mkdir -p $(dir $@)
	printf '%s\n\n%s\n' \
		'$(DERAMMO_AGENT_CMAKE_ROOT_SENTENCE)' \
		'@../../$(DERAMMO_AGENT_CMAKE_ROOT)cmake/docs/agent_instructions.md' > $@

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
	