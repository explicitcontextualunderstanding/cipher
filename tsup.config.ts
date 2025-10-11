import { defineConfig } from 'tsup';

// Esbuild plugin to resolve .js import specifiers to .ts sources
const jsToTsResolverPlugin = {
	name: 'js-to-ts-resolver',
	setup(build: any) {
		build.onResolve({ filter: /\.js$/ }, (args: any) => {
			// Only resolve relative imports (node_modules should remain untouched)
			if (args.path.startsWith('./') || args.path.startsWith('../')) {
				const tsPath = args.path.replace(/\.js$/, '.ts');
				const resolvedPath = build.resolve(tsPath, {
					resolveDir: args.resolveDir,
					kind: args.kind,
				});

				if (resolvedPath.path) {
					return resolvedPath;
				}
			}

			// Fall back to default resolution
			return build.resolve(args.path, {
				resolveDir: args.resolveDir,
				kind: args.kind,
			});
		});
	},
};

export default defineConfig([
	{
		entry: ['src/core/index.ts'],
		format: ['cjs', 'esm'],
		outDir: 'dist/src/core',
		dts: true,
		shims: true,
		bundle: true, // Re-enable bundling for proper module resolution
		// Temporarily disable custom plugin to isolate the issue
		// esbuildPlugins: [jsToTsResolverPlugin],
		esbuildOptions(options) {
			// Ensure esbuild can resolve .js import specifiers
			// against TypeScript source files in a NodeNext
			// ESM project.
			options.resolveExtensions = ['.ts', '.tsx', '.js', '.jsx', '.json'];
		},
		noExternal: ['chalk', 'boxen'],
		external: ['better-sqlite3', 'pg', 'redis'],
		// Optimize splitting for better memory usage
		splitting: false,
		minify: false, // Skip minification to reduce memory usage during build
		// Reduce concurrency to prevent memory spikes
		concurrency: 1,
	},
	{
		entry: ['src/app/index.ts'],
		format: ['cjs'], // Use only CommonJS for app to avoid dynamic require issues
		outDir: 'dist/src/app',
		shims: true,
		bundle: true, // Re-enable bundling for proper module resolution
		// Temporarily disable custom plugin to isolate the issue
		// esbuildPlugins: [jsToTsResolverPlugin],
		esbuildOptions(options) {
			options.resolveExtensions = ['.ts', '.tsx', '.js', '.jsx', '.json'];
		},
		platform: 'node',
		target: 'node18', // Specify Node.js target version
		external: [
			// Database drivers
			'better-sqlite3',
			'pg',
			'neo4j-driver',
			'ioredis',
			// Node.js built-in modules to prevent bundling issues
			'fs',
			'path',
			'os',
			'crypto',
			'stream',
			'util',
			'events',
			'child_process',
		],
		noExternal: ['chalk', 'boxen', 'commander'],
		// Optimize splitting for better memory usage
		splitting: false,
		minify: false, // Skip minification to reduce memory usage during build
		// Reduce concurrency to prevent memory spikes
		concurrency: 1,
	},
]);
