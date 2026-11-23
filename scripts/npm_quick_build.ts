#!/usr/bin/env node
// Runs the build steps of an npm package and records the completed build in
// a stamp file; with QUICK set in the environment, skips all of the steps
// when the package is up to date. Used by the build targets of
// derammo_npm.cmake. Run directly by node without compilation (type
// stripping).
//
//   node npm_quick_build.ts <package-dir> <stamp-file> <step...> [+++ <step...>]...
//
// Each `+++` separates one command line from the next; the steps run in order
// in the current working directory, stopping at the first failure, exactly as
// the build target would run them as plain commands.
//
// QUICK in the environment (any value except empty or 0) turns the check on;
// without it the steps always run. The stamp, written when the steps
// complete in either mode so a full build keeps it fresh, belongs in the
// build tree: its modification time is the time of the last completed build,
// and its content records the dependency state installed then, as the hash
// of the nearest package-lock.json and of each tarball dependency.
//
// The package is up to date when the build script chain in its package.json
// leads to a single `tsc -p <config>` invocation whose incremental build info
// exists, every input is older than the stamp of the last completed build,
// the dependency state matches the stamp, and the recorded outputs still
// exist. The inputs are the files listed in the build info, the tsconfig
// extends chain, and package.json itself. The stamp, not the build info, is
// the mtime baseline because tsc leaves the build info untouched when a
// rebuild changes nothing; the dependency state is compared by content
// because npm freshens the lock file on every install and `npm pack`
// freshens the tarballs on every provider build, reproducing the same bytes
// when nothing changed. Anything unrecognized, unreadable, or missing makes
// the package stale, so an analysis failure costs a build that may not have
// been needed; an input that none of the records can show (for example a
// tool invoked by an unrecognized build script) is invisible here, which is
// why skipping is opt-in per build.

import { spawnSync } from "node:child_process";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";

const STEP_SEPARATOR = "+++";
const SOURCE_EXTENSIONS = [".ts", ".tsx", ".mts", ".cts"];
// matches the indentation of the echo in the build scripts of the standard
// package templates, so the skip and build lines align with their output
const MESSAGE_INDENT = "       ";

type JsonObject = { [key: string]: unknown };

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

// blanks out comments and trailing commas, which tsconfig files may contain,
// replacing them with spaces so JSON.parse error offsets stay meaningful
function stripJsonComments(text: string): string {
  const output = text.split("");
  let index = 0;
  let inString = false;
  let lastComma = -1;
  while (index < text.length) {
    const character = text[index];
    if (inString) {
      if (character === "\\") {
        index += 2;
        continue;
      }
      if (character === '"') {
        inString = false;
      }
      index++;
      continue;
    }
    if (character === '"') {
      inString = true;
      lastComma = -1;
      index++;
      continue;
    }
    if (character === "/" && text[index + 1] === "/") {
      while (index < text.length && text[index] !== "\n") {
        output[index] = " ";
        index++;
      }
      continue;
    }
    if (character === "/" && text[index + 1] === "*") {
      while (index < text.length && !(text[index] === "*" && text[index + 1] === "/")) {
        if (text[index] !== "\n") {
          output[index] = " ";
        }
        index++;
      }
      output[index] = " ";
      output[index + 1] = " ";
      index += 2;
      continue;
    }
    if (character === ",") {
      lastComma = index;
    } else if (character === "}" || character === "]") {
      if (lastComma >= 0) {
        output[lastComma] = " ";
      }
      lastComma = -1;
    } else if (!/\s/.test(character)) {
      lastComma = -1;
    }
    index++;
  }
  return output.join("");
}

function readJsonFile(filePath: string, allowComments: boolean): JsonObject | undefined {
  let text: string;
  try {
    text = fs.readFileSync(filePath, "utf8");
  } catch {
    return undefined;
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(allowComments ? stripJsonComments(text) : text);
  } catch {
    return undefined;
  }
  return isJsonObject(parsed) ? parsed : undefined;
}

function modifiedTime(filePath: string): number | undefined {
  const stats = fs.statSync(filePath, { throwIfNoEntry: false });
  return stats?.mtimeMs;
}

function fileHash(filePath: string): string | undefined {
  let content: Buffer;
  try {
    content = fs.readFileSync(filePath);
  } catch {
    return undefined;
  }
  return crypto.createHash("sha256").update(content).digest("hex");
}

// the single tsc invocation a recognized build script chain runs
interface TscInvocation {
  configPath: string;
  packsTarball: boolean;
}

// follows the package.json build script through `npm run` indirections,
// accepting only the shapes the standard package templates produce: echo,
// `npm run <script>`, one tsc or tsc-absolute project build, and the
// `npm pack` plus `ln -sf` tail of the tarball template; anything else makes
// the chain unanalyzable, so the package always builds
class BuildScriptAnalyzer {
  private readonly packageDir: string;
  private readonly scripts: JsonObject;
  private readonly visited: Set<string> = new Set();
  private configPath: string | undefined;
  private packsTarball = false;

  constructor(packageDir: string, scripts: unknown) {
    this.packageDir = packageDir;
    this.scripts = isJsonObject(scripts) ? scripts : {};
  }

  analyze(): TscInvocation | undefined {
    if (!this.analyzeScript("build") || this.configPath === undefined) {
      return undefined;
    }
    return { configPath: this.configPath, packsTarball: this.packsTarball };
  }

  private analyzeScript(name: string): boolean {
    if (this.visited.has(name)) {
      return true;
    }
    this.visited.add(name);
    const script = this.scripts[name];
    if (typeof script !== "string") {
      return false;
    }
    return script
      .split("&&")
      .map((part) => part.trim())
      .every((segment) => this.analyzeSegment(segment));
  }

  private analyzeSegment(segment: string): boolean {
    if (segment === "" || segment.startsWith("echo ") || segment.startsWith("ln -sf ")) {
      return true;
    }
    if (segment === "TARBALL=$(npm pack --quiet)") {
      this.packsTarball = true;
      return true;
    }
    const run = segment.match(/^npm run ([A-Za-z0-9:._-]+)$/);
    if (run !== null) {
      return this.analyzeScript(run[1]);
    }
    const words = segment.split(/\s+/);
    const command = path.basename(words[0]);
    if (command === "tsc" || command === "tsc-absolute") {
      return this.analyzeTsc(words.slice(1));
    }
    return false;
  }

  private analyzeTsc(args: string[]): boolean {
    let config = "tsconfig.json";
    for (let index = 0; index < args.length; index++) {
      const arg = args[index];
      if (arg === "-b" || arg === "--build" || arg === "-w" || arg === "--watch" || arg === "--noEmit") {
        return false;
      }
      if (arg === "-p" || arg === "--project") {
        const value: string | undefined = args[index + 1];
        if (value === undefined) {
          return false;
        }
        config = value;
        index++;
      }
    }
    const configPath = path.resolve(this.packageDir, config);
    if (this.configPath !== undefined && this.configPath !== configPath) {
      return false;
    }
    this.configPath = configPath;
    return true;
  }
}

// the tsconfig files contributing to a project build, and the merged
// compiler options the staleness check needs from them
interface TsconfigChain {
  configFiles: string[];
  tsBuildInfoFile: string | undefined;
  incremental: boolean;
}

// walks a tsconfig extends chain, leaf first so nearer configs win for the
// options collected; only relative extends entries are supported, an entry
// naming an npm package makes the chain unanalyzable
class TsconfigResolver {
  private readonly visited: Set<string> = new Set();
  private readonly configFiles: string[] = [];
  private tsBuildInfoFile: string | undefined;
  private incremental: boolean | undefined;

  resolve(configPath: string): TsconfigChain | undefined {
    if (!this.visit(configPath)) {
      return undefined;
    }
    return {
      configFiles: this.configFiles,
      tsBuildInfoFile: this.tsBuildInfoFile,
      incremental: this.incremental === true,
    };
  }

  private visit(configPath: string): boolean {
    const resolved = this.resolveConfigFile(configPath);
    if (resolved === undefined) {
      return false;
    }
    if (this.visited.has(resolved)) {
      return true;
    }
    this.visited.add(resolved);
    const config = readJsonFile(resolved, true);
    if (config === undefined) {
      return false;
    }
    this.configFiles.push(resolved);
    const options = config["compilerOptions"];
    if (isJsonObject(options)) {
      if (this.tsBuildInfoFile === undefined && typeof options["tsBuildInfoFile"] === "string") {
        this.tsBuildInfoFile = path.resolve(path.dirname(resolved), options["tsBuildInfoFile"]);
      }
      if (this.incremental === undefined) {
        if (typeof options["incremental"] === "boolean") {
          this.incremental = options["incremental"];
        } else if (options["composite"] === true) {
          this.incremental = true;
        }
      }
    }
    const extendsValue = config["extends"];
    const entries = typeof extendsValue === "string" ? [extendsValue] : Array.isArray(extendsValue) ? extendsValue : [];
    for (const entry of entries) {
      if (typeof entry !== "string") {
        return false;
      }
      if (!entry.startsWith("./") && !entry.startsWith("../") && !path.isAbsolute(entry)) {
        return false;
      }
      if (!this.visit(path.resolve(path.dirname(resolved), entry))) {
        return false;
      }
    }
    return true;
  }

  // extends entries may leave off the .json extension
  private resolveConfigFile(configPath: string): string | undefined {
    if (fs.existsSync(configPath)) {
      return configPath;
    }
    if (!configPath.endsWith(".json") && fs.existsSync(configPath + ".json")) {
      return configPath + ".json";
    }
    return undefined;
  }
}

// what the staleness check reads from a tsc incremental build info file:
// the inputs of the last build and the output directory, made absolute
interface BuildInfoInputs {
  fileNames: string[];
  outDir: string | undefined;
}

function readBuildInfo(buildInfoPath: string): BuildInfoInputs | undefined {
  const data = readJsonFile(buildInfoPath, false);
  if (data === undefined) {
    return undefined;
  }
  // tsc wrote the program at the top level in some versions and nested in
  // others; paths are relative to the directory holding the build info
  const program = isJsonObject(data["program"]) ? data["program"] : data;
  const fileNames = program["fileNames"];
  if (!Array.isArray(fileNames) || !fileNames.every((name) => typeof name === "string")) {
    return undefined;
  }
  const baseDir = path.dirname(buildInfoPath);
  const options = isJsonObject(program["options"]) ? program["options"] : {};
  const outDir = typeof options["outDir"] === "string" ? path.resolve(baseDir, options["outDir"]) : undefined;
  return {
    fileNames: (fileNames as string[]).map((name) => path.resolve(baseDir, name)),
    outDir,
  };
}

// decides whether the package in a directory must build, and records the
// stamp that later checks measure against once a build completes
class QuickCheck {
  private readonly packageDir: string;
  private readonly stampPath: string;
  private readonly manifest: JsonObject | undefined;

  constructor(packageDir: string, stampPath: string) {
    this.packageDir = packageDir;
    this.stampPath = stampPath;
    this.manifest = readJsonFile(path.join(packageDir, "package.json"), false);
  }

  describePackage(): string {
    const name = this.manifest?.["name"];
    return typeof name === "string" ? `'${name}'` : `npm package in '${this.packageDir}'`;
  }

  // null when the package is up to date; otherwise the reason to build
  staleReason(): string | null {
    if (this.manifest === undefined) {
      return "package.json is unreadable";
    }
    const invocation = new BuildScriptAnalyzer(this.packageDir, this.manifest["scripts"]).analyze();
    if (invocation === undefined) {
      return "the build script is not a recognized tsc project build";
    }
    const chain = new TsconfigResolver().resolve(invocation.configPath);
    if (chain === undefined) {
      return `the tsconfig chain of ${this.relative(invocation.configPath)} could not be read`;
    }
    if (!chain.incremental) {
      return `${this.relative(invocation.configPath)} does not enable incremental build info`;
    }
    const buildInfoPath = chain.tsBuildInfoFile ?? this.defaultBuildInfoPath(invocation.configPath);
    const buildInfoTime = modifiedTime(buildInfoPath);
    if (buildInfoTime === undefined) {
      return `${this.relative(buildInfoPath)} does not exist yet`;
    }
    const stampTime = modifiedTime(this.stampPath);
    if (stampTime === undefined) {
      return "no completed build is stamped yet";
    }
    const stamp = readJsonFile(this.stampPath, false);
    if (stamp === undefined) {
      return "the stamp of the last completed build is unreadable";
    }
    // npm install freshens the lock file's timestamp even when it changes
    // nothing, and the workspace install runs on every build, so the lock
    // is compared by content against the hash the stamp recorded
    if (this.lockFileHash() !== stamp["lockFileHash"]) {
      return "the nearest package-lock.json changed";
    }
    if (buildInfoTime > stampTime) {
      return `${this.relative(buildInfoPath)} was written since the last completed build`;
    }
    const buildInfo = readBuildInfo(buildInfoPath);
    if (buildInfo === undefined) {
      return `${this.relative(buildInfoPath)} is not in a readable format`;
    }
    return (
      this.changedInputReason([path.join(this.packageDir, "package.json"), ...chain.configFiles], stampTime) ??
      this.listedInputReason(buildInfo.fileNames, stampTime) ??
      this.newSourceReason(buildInfo.fileNames, stampTime) ??
      this.tarballDependencyReason(stamp) ??
      this.missingOutputReason(buildInfo, invocation)
    );
  }

  // the build ran to completion, so inputs older than now are accounted for;
  // called after full builds too, so the quick state is fresh either way
  writeStamp(): void {
    const content = {
      comment:
        "last completed npm package build, recorded by cmake/scripts/npm_quick_build.ts; " +
        "the modification time of this file is the build time",
      lockFileHash: this.lockFileHash() ?? null,
      tarballHashes: this.tarballHashes(),
    };
    try {
      fs.mkdirSync(path.dirname(this.stampPath), { recursive: true });
      fs.writeFileSync(this.stampPath, JSON.stringify(content, null, 2) + "\n");
    } catch (error) {
      console.error(`${MESSAGE_INDENT}could not write ${this.stampPath}: ${(error as Error).message}`);
    }
  }

  private relative(filePath: string): string {
    const relativePath = path.relative(this.packageDir, filePath);
    return relativePath.startsWith("..") ? filePath : relativePath;
  }

  // tsc names the default build info after the config file
  private defaultBuildInfoPath(configPath: string): string {
    const withoutExtension = configPath.endsWith(".json") ? configPath.slice(0, -".json".length) : configPath;
    return withoutExtension + ".tsbuildinfo";
  }

  private changedInputReason(filePaths: string[], stampTime: number): string | null {
    for (const filePath of filePaths) {
      const time = modifiedTime(filePath);
      if (time === undefined) {
        return `${this.relative(filePath)} is missing`;
      }
      if (time > stampTime) {
        return `${this.relative(filePath)} changed`;
      }
    }
    return null;
  }

  // the nearest lock file records which version of every dependency is
  // installed; for a workspace member it lives at the workspace root
  private lockFileHash(): string | null {
    let directory = this.packageDir;
    for (;;) {
      const lockFile = path.join(directory, "package-lock.json");
      let content: Buffer | undefined;
      try {
        content = fs.readFileSync(lockFile);
      } catch {
        content = undefined;
      }
      if (content !== undefined) {
        return crypto.createHash("sha256").update(this.comparableLockContent(content)).digest("hex");
      }
      const parent = path.dirname(directory);
      if (parent === directory) {
        return null;
      }
      directory = parent;
    }
  }

  // entries resolved from local tarballs are left out of the comparison:
  // every rebuild of a provider changes their recorded integrity, which would
  // make every member of a shared workspace stale, while only the consumers
  // of the tarball need to build and their own tarball check already sees it
  private comparableLockContent(content: Buffer): string | Buffer {
    let parsed: unknown;
    try {
      parsed = JSON.parse(content.toString("utf8"));
    } catch {
      return content;
    }
    if (!isJsonObject(parsed)) {
      return content;
    }
    const packages = parsed["packages"];
    if (isJsonObject(packages)) {
      for (const key of Object.keys(packages)) {
        const entry = packages[key];
        if (isJsonObject(entry) && typeof entry["resolved"] === "string" && entry["resolved"].endsWith(".tgz")) {
          delete packages[key];
        }
      }
    }
    return JSON.stringify(parsed);
  }

  private listedInputReason(fileNames: string[], stampTime: number): string | null {
    return this.changedInputReason(fileNames, stampTime);
  }

  // a source file the build info does not list is found by scanning the
  // package directories that contributed listed sources; only files newer
  // than the stamp count, so files the project build intentionally excludes,
  // such as tests next to sources, do not keep the package stale forever
  private newSourceReason(fileNames: string[], stampTime: number): string | null {
    const known = new Set(fileNames);
    const topDirectories = new Set<string>();
    for (const fileName of fileNames) {
      const relativePath = path.relative(this.packageDir, fileName);
      if (relativePath.startsWith("..") || path.isAbsolute(relativePath)) {
        continue;
      }
      const segments = relativePath.split(path.sep);
      if (segments.length < 2 || segments[0] === "node_modules") {
        continue;
      }
      topDirectories.add(path.join(this.packageDir, segments[0]));
    }
    for (const directory of topDirectories) {
      const found = this.findUnknownSource(directory, known, stampTime);
      if (found !== null) {
        return `${this.relative(found)} is not in the build info`;
      }
    }
    return null;
  }

  private findUnknownSource(directory: string, known: Set<string>, stampTime: number): string | null {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(directory, { withFileTypes: true });
    } catch {
      return null;
    }
    for (const entry of entries) {
      const entryPath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === "node_modules" || entry.name.startsWith(".")) {
          continue;
        }
        const found = this.findUnknownSource(entryPath, known, stampTime);
        if (found !== null) {
          return found;
        }
      } else if (SOURCE_EXTENSIONS.some((extension) => entry.name.endsWith(extension)) && !known.has(entryPath)) {
        const time = modifiedTime(entryPath);
        if (time !== undefined && time > stampTime) {
          return entryPath;
        }
      }
    }
    return null;
  }

  // a dependency whose version is file:<path>.tgz names a tarball a sibling
  // package build left behind; npm sets the modification times of extracted
  // files to a fixed date, so only the tarball itself shows that the
  // dependency moved, and `npm pack` freshens its timestamp while
  // reproducing the same bytes when nothing changed, so the comparison is
  // by content against the hash the stamp recorded
  private tarballDependencyReason(stamp: JsonObject): string | null {
    const recorded = stamp["tarballHashes"];
    for (const [name, tarballPath] of this.tarballDependencies()) {
      const hash = fileHash(tarballPath);
      if (hash === undefined) {
        return `tarball dependency ${name} is missing`;
      }
      if (!isJsonObject(recorded) || recorded[name] !== hash) {
        return `tarball dependency ${name} changed`;
      }
    }
    return null;
  }

  // the file:<path>.tgz dependencies of the package, as [name, absolute path]
  private tarballDependencies(): [string, string][] {
    const results: [string, string][] = [];
    for (const kind of ["dependencies", "devDependencies"]) {
      const dependencies = this.manifest?.[kind];
      if (!isJsonObject(dependencies)) {
        continue;
      }
      for (const name of Object.keys(dependencies)) {
        const version = dependencies[name];
        if (typeof version !== "string") {
          continue;
        }
        const match = version.match(/^file:(.*\.tgz)$/);
        if (match !== null) {
          results.push([name, path.resolve(this.packageDir, match[1])]);
        }
      }
    }
    return results;
  }

  private tarballHashes(): { [name: string]: string } {
    const hashes: { [name: string]: string } = {};
    for (const [name, tarballPath] of this.tarballDependencies()) {
      const hash = fileHash(tarballPath);
      if (hash !== undefined) {
        hashes[name] = hash;
      }
    }
    return hashes;
  }

  private missingOutputReason(buildInfo: BuildInfoInputs, invocation: TscInvocation): string | null {
    if (buildInfo.outDir !== undefined && !fs.existsSync(buildInfo.outDir)) {
      return `output directory ${this.relative(buildInfo.outDir)} is missing`;
    }
    if (invocation.packsTarball) {
      const name = this.manifest?.["name"];
      if (typeof name !== "string") {
        return "the package packs a tarball but has no name";
      }
      const tarballName = name.replaceAll("@", "").replaceAll("/", "-") + "-current.tgz";
      const tarballPath = path.join(this.packageDir, tarballName);
      if (modifiedTime(tarballPath) === undefined) {
        return `${tarballName} is missing`;
      }
    }
    return null;
  }
}

// runs the build steps the same way the plain build target would: in order,
// in the inherited working directory, stopping at the first failure
class StepRunner {
  private readonly steps: string[][];

  constructor(steps: string[][]) {
    this.steps = steps;
  }

  run(): number {
    for (const step of this.steps) {
      const status = this.runStep(step);
      if (status !== 0) {
        return status;
      }
    }
    return 0;
  }

  private runStep(step: string[]): number {
    const [command, ...args] = step;
    if (command === undefined) {
      return 0;
    }
    // npm and friends are .cmd files on Windows, which only a shell can start
    const result =
      process.platform === "win32"
        ? spawnSync(this.quoteForShell(step), { stdio: "inherit", shell: true })
        : spawnSync(command, args, { stdio: "inherit" });
    if (result.error !== undefined) {
      console.error(`${command}: ${result.error.message}`);
      return 1;
    }
    return result.status ?? 1;
  }

  private quoteForShell(words: string[]): string {
    return words.map((word) => (/[\s"]/.test(word) ? `"${word.replaceAll('"', '\\"')}"` : word)).join(" ");
  }
}

interface ParsedArguments {
  packageDir: string;
  stampPath: string;
  steps: string[][];
}

function parseArguments(argv: string[]): ParsedArguments | undefined {
  if (argv.length < 2) {
    return undefined;
  }
  const packageDir = path.resolve(argv[0]);
  const stampPath = path.resolve(argv[1]);
  const steps: string[][] = [];
  let current: string[] = [];
  for (const argument of argv.slice(2)) {
    if (argument === STEP_SEPARATOR) {
      if (current.length > 0) {
        steps.push(current);
      }
      current = [];
    } else {
      current.push(argument);
    }
  }
  if (current.length > 0) {
    steps.push(current);
  }
  if (steps.length === 0) {
    return undefined;
  }
  return { packageDir, stampPath, steps };
}

// QUICK comes from the environment of the build invocation, so each build
// chooses: `QUICK=1 make` skips up to date packages, plain `make` builds
// everything and refreshes the stamps
function quickRequested(): boolean {
  const value = process.env["QUICK"];
  return value !== undefined && value !== "" && value !== "0";
}

function main(): void {
  const parsed = parseArguments(process.argv.slice(2));
  if (parsed === undefined) {
    console.error(`usage: node npm_quick_build.ts <package-dir> <stamp-file> <step...> [${STEP_SEPARATOR} <step...>]...`);
    process.exit(2);
  }
  const check = new QuickCheck(parsed.packageDir, parsed.stampPath);
  if (quickRequested()) {
    let reason: string;
    try {
      const stale = check.staleReason();
      if (stale === null) {
        console.log(`${MESSAGE_INDENT}${check.describePackage()} is up to date, skipping build`);
        return;
      }
      reason = stale;
    } catch (error) {
      reason = `quick check failed: ${(error as Error).message}`;
    }
    console.log(`${MESSAGE_INDENT}building ${check.describePackage()}: ${reason}`);
  }
  const status = new StepRunner(parsed.steps).run();
  if (status !== 0) {
    process.exit(status);
  }
  check.writeStamp();
}

main();
