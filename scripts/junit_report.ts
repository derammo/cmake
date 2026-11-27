#!/usr/bin/env node
// Turns the JUnit XML files of a test run into a report of one line per test:
// FAIL or nothing in the first column, then what was tested. The lines are
// sorted by what was tested, so the reports of two runs can be compared line
// by line. A test that was skipped is reported like one that passed. Run
// directly by node without compilation (type stripping).
//
//   node junit_report.ts <junit-dir>
//   node junit_report.ts <junit-dir> <archive-dir> <report-file>
//
// <junit-dir> is the folder `ctest --output-junit` and the test providers
// write to: ctest.xml, with one entry per ctest test, and next to it one file
// per test that reports its own cases, named <ctest test>.xml. Every ctest
// test gets a line; a test with a file of its own also gets a line per case.
// The folder is only read.
//
// The first form prints the report. The second writes it to <report-file> and
// copies the XML files into <archive-dir>, without the output that is not
// worth keeping: a case that passed loses its output, and so does an entry of
// ctest.xml whose cases are in a file of their own. A case that failed or was
// skipped is copied whole, and no result is left out.
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

type Result = "pass" | "FAIL" | "skip";

interface TestCase {
	readonly attributes: ReadonlyMap<string, string>;
	readonly result: Result;
}

const TEST_CASE = /<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g;
const CAPTURED_OUTPUT = /\s*<system-(out|err)\b[^>]*?(\/>|>[\s\S]*?<\/system-\1>)/g;
const RANK: Readonly<Record<Result, number>> = { skip: 0, pass: 1, FAIL: 2 };
const ENTITIES: Readonly<Record<string, string>> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

function unescape(text: string): string {
	return text.replace(/&(#x[0-9a-fA-F]+|#[0-9]+|[a-z]+);/g, (whole, name: string) => {
		if (name.startsWith("#x")) {
			return String.fromCodePoint(parseInt(name.slice(2), 16));
		}
		if (name.startsWith("#")) {
			return String.fromCodePoint(parseInt(name.slice(1), 10));
		}
		return ENTITIES[name] ?? whole;
	});
}

// one <testcase> element: a case is failed when it holds a failure or an
// error, or when ctest gave it the status fail
function testCase(attributeText: string, body: string): TestCase {
	const attributes = new Map<string, string>();
	for (const attribute of attributeText.matchAll(/([\w:-]+)="([^"]*)"/g)) {
		attributes.set(attribute[1] ?? "", unescape(attribute[2] ?? ""));
	}
	let result: Result = "pass";
	if (/<(failure|error)\b/.test(body) || attributes.get("status") === "fail") {
		result = "FAIL";
	} else if (/<skipped\b/.test(body) || attributes.get("status") === "notrun") {
		result = "skip";
	}
	return { attributes, result };
}

function testCases(xml: string): TestCase[] {
	return [...xml.matchAll(TEST_CASE)].map((match) => testCase(match[1] ?? "", match[3] ?? ""));
}

// the same XML without the captured output of the cases that `loses` names
function withoutOutput(xml: string, loses: (test: TestCase) => boolean): string {
	return xml.replace(TEST_CASE, (element: string, attributeText: string, _end: string, body: string | undefined) =>
		loses(testCase(attributeText, body ?? "")) ? element.replace(CAPTURED_OUTPUT, "") : element,
	);
}

class TestRun {
	private readonly ctest: string;
	// the XML of each ctest test that reported its own cases, by test name
	private readonly caseFiles = new Map<string, string>();

	constructor(directory: string) {
		this.ctest = readFileSync(join(directory, "ctest.xml"), "utf8");
		const tests = new Set(testCases(this.ctest).map((test) => test.attributes.get("name") ?? ""));
		for (const file of readdirSync(directory)) {
			const name = file.replace(/\.xml$/, "");
			// a file left by a test that is not part of this run says nothing about it
			if (file !== "ctest.xml" && name !== file && tests.has(name)) {
				this.caseFiles.set(name, readFileSync(join(directory, file), "utf8"));
			}
		}
	}

	report(): string {
		const lines = new Map<string, Result>();
		for (const test of testCases(this.ctest)) {
			lines.set(test.attributes.get("name") ?? "", test.result);
		}
		for (const [name, xml] of this.caseFiles) {
			for (const test of testCases(xml)) {
				const key = `${name} :: ${test.attributes.get("classname") ?? ""} :: ${test.attributes.get("name") ?? ""}`;
				// cases that share a name share a line, which shows the worst of them
				const earlier = lines.get(key);
				lines.set(key, earlier === undefined || RANK[test.result] > RANK[earlier] ? test.result : earlier);
			}
		}
		const keys = [...lines.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
		// only a failure marks its line, so that failures stand out
		return keys.map((key) => `${lines.get(key) === "FAIL" ? "FAIL" : "    "}  ${key}\n`).join("");
	}

	archive(directory: string): void {
		mkdirSync(directory, { recursive: true });
		const passed = (test: TestCase): boolean => test.result === "pass";
		writeFileSync(
			join(directory, "ctest.xml"),
			withoutOutput(this.ctest, (test) => passed(test) || this.caseFiles.has(test.attributes.get("name") ?? "")),
		);
		for (const [name, xml] of this.caseFiles) {
			writeFileSync(join(directory, `${name}.xml`), withoutOutput(xml, passed));
		}
	}
}

function main(argv: readonly string[]): number {
	const [junitDirectory, archiveDirectory, reportFile] = argv;
	if (junitDirectory === undefined || (argv.length !== 1 && argv.length !== 3)) {
		console.error("usage: node junit_report.ts <junit-dir> [<archive-dir> <report-file>]");
		return 2;
	}
	if (!existsSync(join(junitDirectory, "ctest.xml"))) {
		console.error(`junit_report: no ctest.xml in ${junitDirectory}; run the tests first`);
		return 1;
	}
	const run = new TestRun(junitDirectory);
	if (archiveDirectory === undefined || reportFile === undefined) {
		process.stdout.write(run.report());
		return 0;
	}
	run.archive(archiveDirectory);
	writeFileSync(reportFile, run.report());
	return 0;
}

process.exitCode = main(process.argv.slice(2));
