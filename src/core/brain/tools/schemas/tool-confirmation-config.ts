/**
 * Tool Confirmation Configuration Schema
 * 
 * Zod schemas for validating tool confirmation configuration.
 */

import { z } from 'zod';

/**
 * Tool confirmation mode schema
 */
export const ToolConfirmationModeSchema = z.enum(['event-based', 'auto-approve', 'auto-deny']);

/**
 * Allowed tools storage backend schema
 */
export const AllowedToolsStorageSchema = z.enum(['memory', 'storage']);

/**
 * Default action schema
 */
export const DefaultActionSchema = z.enum(['approve', 'deny', 'ask']);

/**
 * Tool confirmation configuration schema
 */
export const ToolConfirmationConfigSchema = z.object({
	/**
	 * Confirmation mode
	 */
	mode: ToolConfirmationModeSchema.default('event-based'),
	
	/**
	 * Timeout for confirmation requests in milliseconds
	 */
	timeout: z.number().min(1000).max(300000).default(30000),
	
	/**
	 * Storage backend for allowed tools
	 */
	allowedToolsStorage: AllowedToolsStorageSchema.default('storage'),
	
	/**
	 * Whether to enable session-scoped permissions
	 */
	enableSessionScoping: z.boolean().default(true),
	
	/**
	 * Default action for unknown tools
	 */
	defaultAction: DefaultActionSchema.default('ask'),
});

/**
 * Tool prefixing configuration schema
 */
export const ToolPrefixingConfigSchema = z.object({
	/**
	 * Prefix for MCP tools
	 */
	mcpPrefix: z.string().min(1).max(20).default('mcp--'),
	
	/**
	 * Prefix for internal tools
	 */
	internalPrefix: z.string().min(1).max(20).default('internal--'),
	
	/**
	 * Whether to enable universal prefixing
	 */
	enabled: z.boolean().default(true),
	
	/**
	 * Whether to maintain backward compatibility with cipher_ prefix
	 */
	backwardCompatibility: z.boolean().default(true),
});

/**
 * Internal tools configuration schema
 */
export const InternalToolsConfigSchema = z.object({
	/**
	 * Whether internal tools are enabled
	 */
	enabled: z.boolean().default(true),
	
	/**
	 * Service injection configuration
	 */
	services: z.object({
		/**
		 * Whether to inject embedding manager
		 */
		embeddingManager: z.boolean().default(true),
		
		/**
		 * Whether to inject vector store manager
		 */
		vectorStoreManager: z.boolean().default(true),
		
		/**
		 * Whether to inject LLM service
		 */
		llmService: z.boolean().default(true),
		
		/**
		 * Whether to inject knowledge graph manager
		 */
		knowledgeGraphManager: z.boolean().default(true),
		
		/**
		 * Whether to inject session manager
		 */
		sessionManager: z.boolean().default(true),
		
		/**
		 * Whether to inject file service
		 */
		fileService: z.boolean().default(true),
	}).default({}),
	
	/**
	 * Tool registration configuration
	 */
	registration: z.object({
		/**
		 * Whether to auto-register built-in tools
		 */
		autoRegister: z.boolean().default(true),
		
		/**
		 * Custom tool directories to scan
		 */
		customDirectories: z.array(z.string()).default([]),
		
		/**
		 * Tools to exclude from registration
		 */
		excludeTools: z.array(z.string()).default([]),
	}).default({}),
});

/**
 * Unified tools configuration schema
 */
export const UnifiedToolsConfigSchema = z.object({
	/**
	 * Tool confirmation configuration
	 */
	confirmation: ToolConfirmationConfigSchema.default({}),
	
	/**
	 * Tool prefixing configuration
	 */
	prefixing: ToolPrefixingConfigSchema.default({}),
	
	/**
	 * Internal tools configuration
	 */
	internalTools: InternalToolsConfigSchema.default({}),
	
	/**
	 * Whether to enable MCP tools
	 */
	enableMcpTools: z.boolean().default(true),
	
	/**
	 * Whether to enable internal tools
	 */
	enableInternalTools: z.boolean().default(true),
	
	/**
	 * Operating mode
	 */
	mode: z.enum(['cli', 'default', 'aggregator', 'api']).default('default'),
	
	/**
	 * Execution timeout in milliseconds
	 */
	executionTimeout: z.number().min(1000).max(300000).default(30000),
	
	/**
	 * Conflict resolution strategy
	 */
	conflictResolution: z.enum(['prefix-internal', 'prefer-internal', 'prefer-mcp', 'error']).default('prefix-internal'),
});

/**
 * Type exports for TypeScript
 */
export type ToolConfirmationConfig = z.infer<typeof ToolConfirmationConfigSchema>;
export type ToolPrefixingConfig = z.infer<typeof ToolPrefixingConfigSchema>;
export type InternalToolsConfig = z.infer<typeof InternalToolsConfigSchema>;
export type UnifiedToolsConfig = z.infer<typeof UnifiedToolsConfigSchema>;
