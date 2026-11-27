# Working in a project that is built with these cmake modules

- Build with `make` at the project root. Run all tests with `make test`.
- Your deliverable is a commit of `test-report.txt`. When your task is done and everything is committed, run `make test-report.txt` at the project root and commit the `test-report.txt` it writes.
- `make test-report.txt` wants a clean tree before and after its build. Commit what the build changed, such as lock files and released artifacts, and run it again.
- The report has one line per test, with `FAIL` in the first column for a failing one. Compare it with the committed one to see what your work changed.
- The JUnit XML of the run is in `<platform>/Debug/junit/`. Earlier runs are in `.derammo/test-history/<platform>/<commit>/`.
