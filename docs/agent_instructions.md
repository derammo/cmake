# Working in a project that is built with these cmake modules

Build and test through `make` at the cmake root. The cmake root is the folder that contains the `./cmake/` submodule, not the `cmake` folder itself.

| When                      | Run                                             | cwd                |
|---------------------------|-------------------------------------------------|--------------------|
| iterating on a change     | `make debug`                                    | cmake root         |
| running all tests         | `make test`                                     | cmake root         |
| running one kind of test  | `make test-<label>`, such as `make test-vitest` | cmake root         |
| listing the kinds of test | `ctest --print-labels`                          | `<platform>/Debug` |
| running one test          | `ctest -R <name>`                               | `<platform>/Debug` |
| listing the tests         | `ctest -N`                                      | `<platform>/Debug` |
| checking style            | `make lint`                                     | cmake root         |
| fixing formatting         | `make format`                                   | cmake root         |

`make test` on a clean tree also writes `test-report.txt`: one line per test, with `FAIL` in the first column for a failing one. The JUnit XML of a run is in `<platform>/Debug/junit/`. Earlier runs may be in `.derammo/test-history/<platform>/<commit>/`.

## If you are working unattended

Your deliverable is a commit of `test-report.txt`. When your task is done and everything is committed, run `make test-report.txt` and commit the `test-report.txt` it writes.

- `make test-report.txt` wants a clean tree before and after its build. Commit what the build changed, such as lock files and released artifacts, and run it again.
- Compare the report with the committed one to see what your work changed.

## If the project uses npm packages

- Don't edit a `package.json`. The build writes each one from the `_package_template.json` beside it, and the templates that one extends, so an edit is overwritten by the next build. Edit the template.
- A package that depends on another package of the project gets it as a tarball that the root build packs. That is why a package is built and tested through the root build, where the packages are built in order.
- When a package changes, the lock files of the packages that depend on it change too. They belong to your change; commit them.
- `QUICK=1 make debug` skips the packages whose inputs are unchanged.
