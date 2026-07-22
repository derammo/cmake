#!/usr/bin/env node
// Generates package.json in the current directory from _package_template.json,
// merging any templates listed in its "extends" array. Extended templates are
// merged in array order, and the extending template itself has the highest
// precedence. Run directly by node without compilation (type stripping).
//
// Environment:
//   DERAMMO_NPM_PACKAGE_TEMPLATE_PATH
//     colon separated priority list of folders (first match wins) searched for
//     templates referenced in "extends" without a path component; entries
//     referencing folders that don't exist are silently ignored
//   DERAMMO_NPM_WORKSPACES
//     optional JSON array of workspace folders to merge into the "workspaces"
//     field, used when generating for a workspace root

import * as fs from "node:fs";
import * as path from "node:path";

const TEMPLATE_FILENAME = "_package_template.json";
const OUTPUT_FILENAME = "package.json";

type JsonObject = { [key: string]: unknown };

function isJsonObject(value: unknown): value is JsonObject {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

// arrays and scalars are overwritten, not concatenated, so overriding templates
// can remove items or strictly control order
function deepMerge(target: unknown, source: unknown): unknown {
	if (!isJsonObject(target) || !isJsonObject(source)) {
		return source;
	}
	const output: JsonObject = { ...target };
	for (const key of Object.keys(source)) {
		if (key === "__proto__" || key === "constructor" || key === "prototype") {
			continue;
		}
		output[key] = key in target ? deepMerge(target[key], source[key]) : source[key];
	}
	return output;
}

function loadJson(filePath: string): JsonObject {
	let parsed: unknown;
	try {
		parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
	} catch (error) {
		console.error(`Error reading ${filePath}: ${(error as Error).message}`);
		process.exit(1);
	}
	if (!isJsonObject(parsed)) {
		console.error(`Error: ${filePath} does not contain a JSON object`);
		process.exit(1);
	}
	return parsed;
}

function canonicalStringify(value: JsonObject): string {
	return JSON.stringify(
		value,
		(_key, item) => {
			if (isJsonObject(item)) {
				const sortedObject: JsonObject = {};
				for (const key of Object.keys(item).sort()) {
					sortedObject[key] = item[key];
				}
				return sortedObject;
			}
			return item;
		},
		2,
	);
}

class PackageJsonGenerator {
	private readonly searchPath: string[];
	private readonly visiting: Set<string> = new Set();

	constructor(templatePathSpec: string) {
		this.searchPath = templatePathSpec
			.split(":")
			.filter((entry) => entry.length > 0)
			.map((entry) => path.resolve(entry))
			.filter((entry) => fs.existsSync(entry));
	}

	generate(packageDirectory: string, workspaces: string[] | undefined): void {
		const templatePath = path.join(packageDirectory, TEMPLATE_FILENAME);
		if (!fs.existsSync(templatePath)) {
			console.error(`Error: ${TEMPLATE_FILENAME} not found in ${packageDirectory}`);
			process.exit(1);
		}
		let result: JsonObject = this.loadTemplate(templatePath);
		if (workspaces !== undefined) {
			result = deepMerge(result, { workspaces }) as JsonObject;
		}

		// the output is read only to discourage editing a generated file, so any
		// previous generation must be removed before writing
		const outputPath = path.join(packageDirectory, OUTPUT_FILENAME);
		fs.rmSync(outputPath, { force: true });
		fs.writeFileSync(outputPath, canonicalStringify(result) + "\n");
		fs.chmodSync(outputPath, 0o444);
	}

	private loadTemplate(templatePath: string): JsonObject {
		if (this.visiting.has(templatePath)) {
			console.error(`Error: circular extends involving ${templatePath}`);
			process.exit(1);
		}
		this.visiting.add(templatePath);

		const template = loadJson(templatePath);
		const extendsValue = template["extends"];
		delete template["extends"];

		let result: JsonObject = {};
		if (extendsValue !== undefined) {
			const entries = Array.isArray(extendsValue) ? extendsValue : [extendsValue];
			for (const entry of entries) {
				if (typeof entry !== "string") {
					console.error(`Error: non-string extends entry in ${templatePath}`);
					process.exit(1);
				}
				const resolved = this.resolveExtends(entry, path.dirname(templatePath));
				result = deepMerge(result, this.loadTemplate(resolved)) as JsonObject;
			}
		}

		this.visiting.delete(templatePath);
		return deepMerge(result, template) as JsonObject;
	}

	// a name without any path component is searched on the template path, first
	// match wins; anything else is resolved relative to the extending template
	private resolveExtends(entry: string, baseDirectory: string): string {
		if (entry.includes("/") || path.isAbsolute(entry)) {
			return path.resolve(baseDirectory, entry);
		}
		for (const directory of this.searchPath) {
			const candidate = path.join(directory, entry);
			if (fs.existsSync(candidate)) {
				return candidate;
			}
		}
		console.error(
			`Error: template '${entry}' not found on template path: ${this.searchPath.join(":")}`,
		);
		process.exit(1);
	}
}

function main(): void {
	const generator = new PackageJsonGenerator(
		process.env["DERAMMO_NPM_PACKAGE_TEMPLATE_PATH"] ?? "",
	);

	let workspaces: string[] | undefined;
	const workspacesJson = process.env["DERAMMO_NPM_WORKSPACES"];
	if (workspacesJson !== undefined && workspacesJson.length > 0) {
		let parsed: unknown;
		try {
			parsed = JSON.parse(workspacesJson);
		} catch (error) {
			console.error(`Error parsing DERAMMO_NPM_WORKSPACES: ${(error as Error).message}`);
			process.exit(1);
		}
		if (!Array.isArray(parsed) || !parsed.every((item) => typeof item === "string")) {
			console.error("Error: DERAMMO_NPM_WORKSPACES must be a JSON array of strings");
			process.exit(1);
		}
		workspaces = parsed;
	}

	generator.generate(process.cwd(), workspaces);
}

main();
