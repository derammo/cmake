#!/usr/bin/env node
// Prints one line per test from the JUnit XML files of a test run: the
// result, then what was tested. The lines are sorted by what was tested, so
// the reports of two runs can be compared line by line. Run directly by node
// without compilation (type stripping).
//
//   node junit_report.ts <junit-dir>
//
// <junit-dir> is the folder `ctest --output-junit` and the test providers
// write to: ctest.xml, with one entry per ctest test, and next to it one file
// per test that reports its own cases, named <ctest test>.xml. Every ctest
// test gets a line; a test with a file of its own also gets a line per case.
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

type Result = "pass" | "FAIL" | "skip";

interface TestCase {
	readonly attributes: ReadonlyMap<string, string>;
	readonly result: Result;
}

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

// the test cases of one JUnit file; a case is failed when it holds a failure
// or an error, or when ctest gave it the status fail
function testCases(path: string): TestCase[] {
	const xml = readFileSync(path, "utf8");
	const cases: TestCase[] = [];
	for (const match of xml.matchAll(/<testcase\b([^>]*?)(\/>|>([\s\S]*?)<\/testcase>)/g)) {
		const attributes = new Map<string, string>();
		for (const attribute of (match[1] ?? "").matchAll(/([\w:-]+)="([^"]*)"/g)) {
			attributes.set(attribute[1] ?? "", unescape(attribute[2] ?? ""));
		}
		const body = match[3] ?? "";
		let result: Result = "pass";
		if (/<(failure|error)\b/.test(body) || attributes.get("status") === "fail") {
			result = "FAIL";
		} else if (/<skipped\b/.test(body) || attributes.get("status") === "notrun") {
			result = "skip";
		}
		cases.push({ attributes, result });
	}
	return cases;
}

function main(argv: readonly string[]): number {
	const [directory] = argv;
	if (argv.length !== 1 || directory === undefined) {
		console.error("usage: node junit_report.ts <junit-dir>");
		return 2;
	}
	const ctestFile = join(directory, "ctest.xml");
	if (!existsSync(ctestFile)) {
		console.error(`junit_report: no ${ctestFile}; run the tests first`);
		return 1;
	}
	const lines = new Map<string, Result>();
	const tests = new Set<string>();
	for (const test of testCases(ctestFile)) {
		const name = test.attributes.get("name") ?? "";
		tests.add(name);
		lines.set(name, test.result);
	}
	for (const file of readdirSync(directory)) {
		const name = file.replace(/\.xml$/, "");
		// a file left by a test that no longer exists says nothing about this run
		if (file === "ctest.xml" || name === file || !tests.has(name)) {
			continue;
		}
		for (const testCase of testCases(join(directory, file))) {
			const group = testCase.attributes.get("classname") ?? "";
			const key = `${name} :: ${group} :: ${testCase.attributes.get("name") ?? ""}`;
			// cases that share a name share a line, which shows the worst of them
			const earlier = lines.get(key);
			lines.set(key, earlier === undefined || RANK[testCase.result] > RANK[earlier] ? testCase.result : earlier);
		}
	}
	const keys = [...lines.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
	for (const key of keys) {
		console.log(`${lines.get(key)}  ${key}`);
	}
	return 0;
}

process.exitCode = main(process.argv.slice(2));
