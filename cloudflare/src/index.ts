import { env } from "cloudflare:workers";

export default {
	async fetch(request) {
		const path = new URL(request.url);
		if (path.pathname !== "/index.wasm") {
			return env.ASSETS.fetch(request);
		}
		if (request.method !== "GET" && request.method !== "HEAD") {
			return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
		}

		path.pathname = "/index.wasm.gz";
		const compressed = await env.ASSETS.fetch(new Request(path, { method: request.method }));
		if (!compressed.ok) return compressed;

		// Serve the existing gzip stream to browsers; decode it for identity clients.
		const acceptsGzip = (request.cf?.clientAcceptEncoding ?? request.headers.get("Accept-Encoding") ?? "")
			.split(",")
			.some((encoding) => /^\s*gzip\s*(?:;\s*q\s*=\s*(?:1(?:\.0*)?|0\.\d*[1-9]\d*)\s*)?$/i.test(encoding));
		const headers = new Headers({
			"Content-Type": "application/wasm",
			"Cache-Control": "no-cache",
			Vary: "Accept-Encoding",
		});
		if (acceptsGzip) headers.set("Content-Encoding", "gzip");
		const body = acceptsGzip ? compressed.body : compressed.body?.pipeThrough(new DecompressionStream("gzip"));
		return new Response(body, { headers, encodeBody: "manual" });
	},
} satisfies ExportedHandler;
