/**
 * Tool Prefixing System Tests
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { ToolPrefixingManager } from '../../utils/prefixing.js';
import { ToolPrefixingConfig } from '../../confirmation/types.js';

describe('ToolPrefixingManager', () => {
	let prefixingManager: ToolPrefixingManager;
	let config: ToolPrefixingConfig;

	beforeEach(() => {
		config = {
			mcpPrefix: 'mcp--',
			internalPrefix: 'internal--',
			enabled: true,
			backwardCompatibility: true,
		};
		prefixingManager = new ToolPrefixingManager(config);
	});

	describe('applyPrefix', () => {
		it('should apply MCP prefix to tool name', () => {
			const result = prefixingManager.applyPrefix('filesystem-read', 'mcp');
			expect(result).toBe('mcp--filesystem-read');
		});

		it('should apply internal prefix to tool name', () => {
			const result = prefixingManager.applyPrefix('search-memory', 'internal');
			expect(result).toBe('internal--search-memory');
		});

		it('should not apply prefix if already has one', () => {
			const result = prefixingManager.applyPrefix('mcp--filesystem-read', 'mcp');
			expect(result).toBe('mcp--filesystem-read');
		});

		it('should not apply prefix if disabled', () => {
			config.enabled = false;
			prefixingManager = new ToolPrefixingManager(config);
			
			const result = prefixingManager.applyPrefix('search-memory', 'internal');
			expect(result).toBe('search-memory');
		});
	});

	describe('removePrefix', () => {
		it('should remove MCP prefix', () => {
			const result = prefixingManager.removePrefix('mcp--filesystem-read');
			expect(result.originalName).toBe('filesystem-read');
			expect(result.source).toBe('mcp');
			expect(result.wasModified).toBe(true);
			expect(result.prefix).toBe('mcp--');
		});

		it('should remove internal prefix', () => {
			const result = prefixingManager.removePrefix('internal--search-memory');
			expect(result.originalName).toBe('search-memory');
			expect(result.source).toBe('internal');
			expect(result.wasModified).toBe(true);
			expect(result.prefix).toBe('internal--');
		});

		it('should handle backward compatibility with cipher_ prefix', () => {
			const result = prefixingManager.removePrefix('cipher_search-memory');
			expect(result.originalName).toBe('search-memory');
			expect(result.source).toBe('internal');
			expect(result.wasModified).toBe(true);
			expect(result.prefix).toBe('cipher_');
		});

		it('should return original name if no prefix found', () => {
			const result = prefixingManager.removePrefix('unknown-tool');
			expect(result.originalName).toBe('unknown-tool');
			expect(result.source).toBe('internal');
			expect(result.wasModified).toBe(false);
		});
	});

	describe('getToolSource', () => {
		it('should identify MCP tools', () => {
			const source = prefixingManager.getToolSource('mcp--filesystem-read');
			expect(source).toBe('mcp');
		});

		it('should identify internal tools', () => {
			const source = prefixingManager.getToolSource('internal--search-memory');
			expect(source).toBe('internal');
		});

		it('should identify cipher_ prefixed tools as internal', () => {
			const source = prefixingManager.getToolSource('cipher_search-memory');
			expect(source).toBe('internal');
		});

		it('should return null for unknown tools', () => {
			const source = prefixingManager.getToolSource('unknown-tool');
			expect(source).toBe(null);
		});
	});

	describe('batchApplyPrefixes', () => {
		it('should apply prefixes to multiple tools', () => {
			const tools = {
				'filesystem-read': { description: 'Read file' },
				'filesystem-write': { description: 'Write file' },
			};

			const result = prefixingManager.batchApplyPrefixes(tools, 'mcp');
			
			expect(result).toHaveProperty('mcp--filesystem-read');
			expect(result).toHaveProperty('mcp--filesystem-write');
			expect(result['mcp--filesystem-read']).toEqual({ description: 'Read file' });
		});
	});

	describe('validateConfig', () => {
		it('should validate correct configuration', () => {
			expect(() => prefixingManager.validateConfig()).not.toThrow();
		});

		it('should throw error for empty prefixes', () => {
			config.mcpPrefix = '';
			prefixingManager = new ToolPrefixingManager(config);
			
			expect(() => prefixingManager.validateConfig()).toThrow();
		});

		it('should throw error for identical prefixes', () => {
			config.mcpPrefix = 'same--';
			config.internalPrefix = 'same--';
			prefixingManager = new ToolPrefixingManager(config);
			
			expect(() => prefixingManager.validateConfig()).toThrow();
		});

		it('should throw error for invalid characters', () => {
			config.mcpPrefix = 'mcp@--';
			prefixingManager = new ToolPrefixingManager(config);
			
			expect(() => prefixingManager.validateConfig()).toThrow();
		});
	});
});
