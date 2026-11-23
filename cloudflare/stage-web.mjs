import { copyFile, mkdir, readFile, stat, writeFile } from "node:fs/promises";
import { gzipSync } from "node:zlib";

const source = new URL("../build/web/", import.meta.url);
const destination = new URL("./public/", import.meta.url);
const maxAssetBytes = 25 * 1024 * 1024;
const files = [
	"index.html",
	"index.js",
	"index.pck",
	"index.png",
	"index.icon.png",
	"index.apple-touch-icon.png",
	"index.audio.worklet.js",
	"index.audio.position.worklet.js",
];

const wasm = await readFile(new URL("index.wasm", source));
const compressed = gzipSync(wasm, { level: 9 });
if (compressed.length > maxAssetBytes) {
	throw new Error(`index.wasm.gz is over the Workers asset limit: ${compressed.length} bytes`);
}
for (const name of files) {
	const { size } = await stat(new URL(name, source));
	if (size > maxAssetBytes) throw new Error(`${name} is over the Workers asset limit: ${size} bytes`);
}

await mkdir(destination, { recursive: true });
for (const name of files) {
	await copyFile(new URL(name, source), new URL(name, destination));
}
await writeFile(new URL("index.wasm.gz", destination), compressed);
console.log(`Staged Web build. Wasm: ${wasm.length} → ${compressed.length} bytes.`);
