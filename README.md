# cmake
my cmake scripts as a submodule

## installation

from the top of any project, run:

```
cp Makefile Makefile.orig
git submodule add https://github.com/derammo/cmake
make -f cmake/setup.make root
make
```

then edit the top level CMakeLists.txt to add your project name, vendor, and contact info

## generating configurations

See targets in cmake/main.make, which are included into the root Makefile of your project.  To create a particular distribution, you can 

```
make Linux/Release
make Linux/Debug
make Darwin/Debug
```
and so on.  Several of the pre-created targets in cmake/Makefile show how you can have cmake run automatically to refresh the make files and then immediately use them by depending on the generated Makefile.

On Windows, just run cmake\make.cmd to generate all configs or run cmake\open.cmd to generate and immediately open solution(s) in Visual Studio. 

## generating targets for subdirectories

To initialize a suitable config for a library/executable/etc, there are make targets to initialize cmake.  For example, if you have a subdirectory "foo" that should be built as a library, you can 

```
cd foo
make -f ../cmake/setup.make library
```

to create a pretty decent default configuration for a library in the current directory.  Similar targets exist for executables and other typical uses for a subdirectory.

