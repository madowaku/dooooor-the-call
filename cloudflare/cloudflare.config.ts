import { bindings, defineConfig } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

export default defineConfig({
	worker: {
		name: "dooooor-the-call",
		compatibilityDate: "2026-11-15",
		entrypoint,
		workersDev: true,
		assets: { runWorkerFirst: ["/index.wasm"] },
		env: {
			ASSETS: bindings.assets(),
		},
	},
});
