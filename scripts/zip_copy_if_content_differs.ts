#!/usr/bin/env node
// Copies a zip archive over an earlier one unless both hold the same files
// with the same content. The times recorded inside an archive are not
// compared, so an archive that was only built again leaves the earlier one in
// place, with its modification time brought up to date. Used by the
// vsix_dist target of derammo_vsix.cmake. Run directly by node without
// compilation (type stripping).
//
//   node zip_copy_if_content_differs.ts <new-archive> <destination-archive>
//
// The archives' entries are compared by name, size and CRC first, so an added
// or removed file is a difference; when those agree, the content of each pair
// of entries decides.
import { closeSync, copyFileSync, existsSync, fstatSync, openSync, readSync, utimesSync } from "node:fs";
import { inflateRawSync } from "node:zlib";

const END_OF_CENTRAL_DIRECTORY = 0x06054b50;
const CENTRAL_DIRECTORY_ENTRY = 0x02014b50;
const LOCAL_FILE_HEADER = 0x04034b50;
const STORED = 0;
const DEFLATED = 8;
// a 32 bit field holding this value has its real value in a zip64 record
const IN_ZIP64_RECORD = 0xffffffff;

interface Entry {
	readonly name: string;
	readonly crc: number;
	readonly size: number;
	readonly compressedSize: number;
	readonly method: number;
	readonly localHeaderOffset: number;
}

class ZipArchive {
	private readonly path: string;
	private readonly file: number;
	// by name, in name order
	readonly entries: ReadonlyMap<string, Entry>;

	constructor(path: string) {
		this.path = path;
		this.file = openSync(path, "r");
		this.entries = this.readCentralDirectory();
	}

	close(): void {
		closeSync(this.file);
	}

	private fail(problem: string): never {
		throw new Error(`${this.path}: ${problem}`);
	}

	private read(offset: number, length: number): Buffer {
		const buffer = Buffer.alloc(length);
		if (readSync(this.file, buffer, 0, length, offset) !== length) {
			this.fail(`cannot read ${length} bytes at ${offset}`);
		}
		return buffer;
	}

	// the end record is the last thing in the file, followed only by a comment
	// of up to 64k
	private endOfCentralDirectory(): Buffer {
		const fileSize = fstatSync(this.file).size;
		const tail = this.read(Math.max(0, fileSize - 22 - 0xffff), Math.min(fileSize, 22 + 0xffff));
		for (let at = tail.length - 22; at >= 0; at--) {
			if (tail.readUInt32LE(at) === END_OF_CENTRAL_DIRECTORY) {
				return tail.subarray(at, at + 22);
			}
		}
		this.fail("not a zip archive: no end of central directory record");
	}

	private readCentralDirectory(): Map<string, Entry> {
		const end = this.endOfCentralDirectory();
		const count = end.readUInt16LE(10);
		const size = end.readUInt32LE(12);
		const offset = end.readUInt32LE(16);
		if (count === 0xffff || size === IN_ZIP64_RECORD || offset === IN_ZIP64_RECORD) {
			this.fail("zip64 archives are not supported");
		}
		const directory = this.read(offset, size);
		const entries: Entry[] = [];
		let at = 0;
		for (let index = 0; index < count; index++) {
			if (directory.readUInt32LE(at) !== CENTRAL_DIRECTORY_ENTRY) {
				this.fail(`central directory entry ${index} is damaged`);
			}
			const nameLength = directory.readUInt16LE(at + 28);
			const extraLength = directory.readUInt16LE(at + 30);
			const commentLength = directory.readUInt16LE(at + 32);
			const entry: Entry = {
				name: directory.toString("utf8", at + 46, at + 46 + nameLength),
				method: directory.readUInt16LE(at + 10),
				crc: directory.readUInt32LE(at + 16),
				compressedSize: directory.readUInt32LE(at + 20),
				size: directory.readUInt32LE(at + 24),
				localHeaderOffset: directory.readUInt32LE(at + 42),
			};
			if (entry.compressedSize === IN_ZIP64_RECORD || entry.size === IN_ZIP64_RECORD || entry.localHeaderOffset === IN_ZIP64_RECORD) {
				this.fail(`zip64 entries are not supported: ${entry.name}`);
			}
			entries.push(entry);
			at += 46 + nameLength + extraLength + commentLength;
		}
		entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
		return new Map(entries.map((entry) => [entry.name, entry]));
	}

	// the sizes come from the central directory, since a local header may
	// leave them to a record that follows the data
	content(entry: Entry): Buffer {
		const header = this.read(entry.localHeaderOffset, 30);
		if (header.readUInt32LE(0) !== LOCAL_FILE_HEADER) {
			this.fail(`local header of ${entry.name} is damaged`);
		}
		const dataOffset = entry.localHeaderOffset + 30 + header.readUInt16LE(26) + header.readUInt16LE(28);
		const data = this.read(dataOffset, entry.compressedSize);
		switch (entry.method) {
			case STORED:
				return data;
			case DEFLATED:
				return inflateRawSync(data);
			default:
				this.fail(`compression method ${entry.method} of ${entry.name} is not supported`);
		}
	}
}

function sameEntries(one: ZipArchive, other: ZipArchive): boolean {
	if (one.entries.size !== other.entries.size) {
		return false;
	}
	for (const [name, entry] of one.entries) {
		const counterpart = other.entries.get(name);
		if (counterpart === undefined || counterpart.size !== entry.size || counterpart.crc !== entry.crc) {
			return false;
		}
	}
	return true;
}

function sameContent(newPath: string, destinationPath: string): boolean {
	const one = new ZipArchive(newPath);
	try {
		const other = new ZipArchive(destinationPath);
		try {
			if (!sameEntries(one, other)) {
				return false;
			}
			// sizes and CRCs agree; the content itself decides
			for (const [name, entry] of one.entries) {
				const counterpart = other.entries.get(name);
				if (counterpart === undefined || !one.content(entry).equals(other.content(counterpart))) {
					return false;
				}
			}
			return true;
		} finally {
			other.close();
		}
	} finally {
		one.close();
	}
}

function main(argv: readonly string[]): number {
	const [newPath, destinationPath] = argv;
	if (argv.length !== 2 || newPath === undefined || destinationPath === undefined) {
		console.error("usage: node zip_copy_if_content_differs.ts <new-archive> <destination-archive>");
		return 2;
	}
	if (existsSync(destinationPath) && sameContent(newPath, destinationPath)) {
		const now = new Date();
		utimesSync(destinationPath, now, now);
	} else {
		copyFileSync(newPath, destinationPath);
	}
	return 0;
}

try {
	process.exitCode = main(process.argv.slice(2));
} catch (error) {
	console.error(`zip_copy_if_content_differs: ${error instanceof Error ? error.message : String(error)}`);
	process.exitCode = 1;
}
