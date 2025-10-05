/**
 * Universal Tool Prefixing System
 * 
 * Handles universal prefixing for MCP and internal tools to prevent naming conflicts.
 */

import { logger } from '../../../../logger/index.js';
import { ToolPrefixingConfig, ToolNameResolution } from '../confirmation/types.js';
import { ToolPrefixingError } from '../errors/tool-errors.js';

/**
 * Universal tool prefixing utility
 */
export class ToolPrefixingManager {
	private config: ToolPrefixingConfig;

	constructor(config: ToolPrefixingConfig) {
		this.config = config;
	}

	/**
	 * Apply universal prefix to tool name
	 */
	applyPrefix(toolName: string, source: 'internal' | 'mcp'): string {
		if (!this.config.enabled) {
			return toolName;
		}

		// Check if tool already has a prefix
		if (this.hasPrefix(toolName)) {
			return toolName;
		}

		// Apply appropriate prefix
		const prefix = source === 'mcp' ? this.config.mcpPrefix : this.config.internalPrefix;
		const prefixedName = `${prefix}${toolName}`;

		logger.debug(`ToolPrefixingManager: Applied prefix to tool '${toolName}'`, {
			originalName: toolName,
			prefixedName,
			source,
			prefix
		});

		return prefixedName;
	}

	/**
	 * Remove universal prefix from tool name
	 */
	removePrefix(toolName: string): ToolNameResolution {
		if (!this.config.enabled) {
			return {
				originalName: toolName,
				resolvedName: toolName,
				source: 'internal', // Default assumption
				wasModified: false
			};
		}

		// Check for MCP prefix
		if (toolName.startsWith(this.config.mcpPrefix)) {
			const originalName = toolName.substring(this.config.mcpPrefix.length);
			return {
				originalName,
				resolvedName: toolName,
				source: 'mcp',
				wasModified: true,
				prefix: this.config.mcpPrefix
			};
		}

		// Check for internal prefix
		if (toolName.startsWith(this.config.internalPrefix)) {
			const originalName = toolName.substring(this.config.internalPrefix.length);
			return {
				originalName,
				resolvedName: toolName,
				source: 'internal',
				wasModified: true,
				prefix: this.config.internalPrefix
			};
		}

		// Handle backward compatibility with cipher_ prefix
		if (this.config.backwardCompatibility && toolName.startsWith('cipher_')) {
			const originalName = toolName.substring('cipher_'.length);
			return {
				originalName,
				resolvedName: toolName,
				source: 'internal',
				wasModified: true,
				prefix: 'cipher_'
			};
		}

		// No prefix found
		return {
			originalName: toolName,
			resolvedName: toolName,
			source: 'internal', // Default assumption
			wasModified: false
		};
	}

	/**
	 * Check if tool name has a universal prefix
	 */
	hasPrefix(toolName: string): boolean {
		return toolName.startsWith(this.config.mcpPrefix) || 
			   toolName.startsWith(this.config.internalPrefix) ||
			   (this.config.backwardCompatibility && toolName.startsWith('cipher_'));
	}

	/**
	 * Get tool source from prefixed name
	 */
	getToolSource(toolName: string): 'internal' | 'mcp' | null {
		if (toolName.startsWith(this.config.mcpPrefix)) {
			return 'mcp';
		}
		if (toolName.startsWith(this.config.internalPrefix)) {
			return 'internal';
		}
		if (this.config.backwardCompatibility && toolName.startsWith('cipher_')) {
			return 'internal';
		}
		return null;
	}

	/**
	 * Resolve tool name with prefix handling
	 */
	resolveToolName(toolName: string, source?: 'internal' | 'mcp'): ToolNameResolution {
		// If source is provided, apply prefix
		if (source) {
			const prefixedName = this.applyPrefix(toolName, source);
			return {
				originalName: toolName,
				resolvedName: prefixedName,
				source,
				wasModified: prefixedName !== toolName,
				prefix: source === 'mcp' ? this.config.mcpPrefix : this.config.internalPrefix
			};
		}

		// Otherwise, try to remove prefix
		return this.removePrefix(toolName);
	}

	/**
	 * Batch apply prefixes to multiple tools
	 */
	batchApplyPrefixes(
		tools: Record<string, any>, 
		source: 'internal' | 'mcp'
	): Record<string, any> {
		const result: Record<string, any> = {};

		for (const [toolName, tool] of Object.entries(tools)) {
			const prefixedName = this.applyPrefix(toolName, source);
			result[prefixedName] = tool;
		}

		logger.debug(`ToolPrefixingManager: Applied prefixes to ${Object.keys(tools).length} tools`, {
			source,
			originalCount: Object.keys(tools).length,
			prefixedCount: Object.keys(result).length
		});

		return result;
	}

	/**
	 * Batch remove prefixes from multiple tools
	 */
	batchRemovePrefixes(tools: Record<string, any>): {
		tools: Record<string, any>;
		resolutions: Record<string, ToolNameResolution>;
	} {
		const result: Record<string, any> = {};
		const resolutions: Record<string, ToolNameResolution> = {};

		for (const [toolName, tool] of Object.entries(tools)) {
			const resolution = this.removePrefix(toolName);
			result[resolution.originalName] = tool;
			resolutions[toolName] = resolution;
		}

		logger.debug(`ToolPrefixingManager: Removed prefixes from ${Object.keys(tools).length} tools`, {
			originalCount: Object.keys(tools).length,
			unprefixedCount: Object.keys(result).length
		});

		return { tools: result, resolutions };
	}

	/**
	 * Validate prefix configuration
	 */
	validateConfig(): void {
		const errors: string[] = [];

		// Check prefix lengths
		if (this.config.mcpPrefix.length === 0) {
			errors.push('MCP prefix cannot be empty');
		}
		if (this.config.internalPrefix.length === 0) {
			errors.push('Internal prefix cannot be empty');
		}

		// Check for prefix conflicts
		if (this.config.mcpPrefix === this.config.internalPrefix) {
			errors.push('MCP and internal prefixes cannot be the same');
		}

		// Check for backward compatibility conflicts
		if (this.config.backwardCompatibility) {
			if (this.config.mcpPrefix === 'cipher_' || this.config.internalPrefix === 'cipher_') {
				errors.push('Cannot use cipher_ as prefix when backward compatibility is enabled');
			}
		}

		// Check for special characters
		const invalidChars = /[^a-zA-Z0-9_-]/;
		if (invalidChars.test(this.config.mcpPrefix)) {
			errors.push('MCP prefix contains invalid characters. Only alphanumeric, underscore, and dash are allowed');
		}
		if (invalidChars.test(this.config.internalPrefix)) {
			errors.push('Internal prefix contains invalid characters. Only alphanumeric, underscore, and dash are allowed');
		}

		if (errors.length > 0) {
			throw new ToolPrefixingError(
				`Prefix configuration validation failed: ${errors.join(', ')}`,
				'',
				undefined,
				{ config: this.config, errors }
			);
		}
	}

	/**
	 * Update configuration
	 */
	updateConfig(config: Partial<ToolPrefixingConfig>): void {
		this.config = { ...this.config, ...config };
		this.validateConfig();
		logger.debug('ToolPrefixingManager: Updated configuration', { config: this.config });
	}

	/**
	 * Get current configuration
	 */
	getConfig(): ToolPrefixingConfig {
		return { ...this.config };
	}
}
