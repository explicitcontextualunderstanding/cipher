/**
 * Unified Tool Manager with Enhanced Security and Confirmation Layer
 * 
 * Production-ready unified tool manager with centralized security, confirmation layer,
 * and universal prefixing system.
 */

import { logger } from '../../logger/index.js';
import { MCPManager } from '../../mcp/manager.js';
import { InternalToolManager } from './manager.js';
import { ToolExecutionResult } from '../../mcp/types.js';
import { EventManager } from '../../events/event-manager.js';
import { SessionEvents } from '../../events/event-types.js';
import { v4 as uuidv4 } from 'uuid';

// Enhanced imports
import type { 
    ToolConfirmationProvider, 
    ToolExecutionDetails, 
    ToolConfirmationConfig,
    UnifiedToolsConfig 
} from './confirmation/types.js';
import { ToolConfirmationFactory } from './confirmation/factory.js';
import { SchemaConverter } from './utils/schema-converter.js';
import { 
    ToolSystemError, 
    ToolNotAllowedError, 
    ToolNotFoundError,
    ToolExecutionError 
} from './errors/tool-errors.js';

export interface UnifiedToolManagerConfig extends UnifiedToolsConfig {
    mode?: 'cli' | 'aggregator' | 'api' | 'default';
    enableMcpTools?: boolean;
    enableInternalTools?: boolean;
    executionTimeout?: number;
    conflictResolution?: 'prefix-internal' | 'prefix-mcp' | 'fail';
    storageBackend?: any;
    services?: {
        embeddingManager?: any;
        vectorStoreManager?: any;
        llmService?: any;
        knowledgeGraphManager?: any;
        sessionManager?: any;
        fileService?: any;
    };
}

export interface CombinedToolSet {
    [toolName: string]: {
        description: string;
        parameters: any;
        source: 'internal' | 'mcp';
        originalName: string;
        prefixed: boolean;
        requiresConfirmation: boolean;
    };
}

interface ToolConfirmationResult {
    approved: boolean;
    preApproved: boolean;
    method: 'user-confirmation' | 'pre-approved' | 'auto-approve' | 'auto-deny';
    confirmationTime: number;
}

export class UnifiedToolManager {
    private mcpManager: MCPManager;
    private internalToolManager: InternalToolManager;
    private confirmationProvider?: ToolConfirmationProvider;
    private config: Required<UnifiedToolManagerConfig>;
    private eventManager?: EventManager;
    private toolsAlreadyLogged = false;
    private initialized = false;
    private toolCache = new Map<string, any>();
    private lastCacheUpdate = 0;
    private cacheTimeout = 60000; // 1 minute

    constructor(
        mcpManager: MCPManager,
        internalToolManager: InternalToolManager,
        config: UnifiedToolManagerConfig = {}
    ) {
        this.mcpManager = mcpManager;
        this.internalToolManager = internalToolManager;
        
        // Set default configuration with enhanced security
        this.config = {
            confirmation: {
                mode: 'event-based',
                timeout: 30000,
                allowedToolsStorage: 'storage',
                requireConfirmationForMcp: true,
                requireConfirmationForInternal: true,
            },
            internalTools: {
                enabledServices: {
                    searchService: true,
                    sessionManager: true,
                    fileService: true,
                    embeddingManager: true,
                },
            },
            prefixing: {
                mcpPrefix: 'mcp--',
                internalPrefix: 'internal--',
                legacyPrefix: 'cipher_',
            },
            mode: 'default',
            enableMcpTools: true,
            enableInternalTools: true,
            executionTimeout: 30000,
            conflictResolution: 'prefix-internal',
            storageBackend: null,
            services: {},
            ...config,
        };
    }

    /**
     * Initialize the unified tool manager with enhanced features
     */
    async initialize(): Promise<void> {
        if (this.initialized) {
            logger.warn('UnifiedToolManager: Already initialized');
            return;
        }

        try {
            logger.info('UnifiedToolManager: Initializing with enhanced security...');

            // Initialize confirmation provider
            if (this.config.confirmation) {
                this.confirmationProvider = ToolConfirmationFactory.createConfirmationProvider(
                    this.config.confirmation
                );
                logger.info('UnifiedToolManager: Confirmation provider initialized');
            }

            this.initialized = true;
            logger.info('UnifiedToolManager: Initialized successfully');
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            logger.error(`UnifiedToolManager: Initialization failed: ${errorMessage}`);
            throw error;
        }
    }

    setEventManager(eventManager: EventManager): void {
        this.eventManager = eventManager;
        
        // Set event manager on confirmation provider if it supports it
        if (this.confirmationProvider && 'setEventManager' in this.confirmationProvider) {
            (this.confirmationProvider as any).setEventManager(eventManager);
        }
    }

	/**
	 * Get all available tools from both sources
	 * Filters tools based on mode:
	 * - CLI mode: Only search tools + MCP tools (background tools excluded from agent access)
	 * - Default MCP mode: Only ask_cipher tool
	 * - Aggregator MCP mode: All tools
	 */
	async getAllTools(): Promise<CombinedToolSet> {
		if (!this.toolsAlreadyLogged && this.config.mode !== 'aggregator') {
			logger.debug('UnifiedToolManager: Getting all tools');
		}
		const combinedTools: CombinedToolSet = {};
		console.log('Tools config args', this.config);
		try {
			// MCP Default mode: Only expose ask_cipher tool
			if (this.config.mode === 'default') {
				// TODO: Add ask_cipher tool implementation
				combinedTools['ask_cipher'] = {
					description: 'Ask Cipher to perform tasks using its internal tools and capabilities',
					parameters: {
						type: 'object',
						properties: {
							query: {
								type: 'string',
								description: 'The task or question to ask Cipher',
							},
						},
						required: ['query'],
					},
					source: 'internal',
				};
				logger.debug('UnifiedToolManager: Default MCP mode - only ask_cipher tool exposed');
				return combinedTools;
			}

        const combinedTools: CombinedToolSet = {};

        try {
            // Get MCP tools with prefixing
            if (this.config.enableMcpTools && this.shouldExposeMcpTools()) {
                const mcpTools = await this.mcpManager.getAllTools();
                
                for (const [originalName, tool] of Object.entries(mcpTools)) {
                    const prefixedName = this.applyPrefix(originalName, 'mcp');
                    
                    combinedTools[prefixedName] = {
                        description: tool.description,
                        parameters: tool.parameters,
                        source: 'mcp',
                        originalName,
                        prefixed: true,
                        requiresConfirmation: await this.requiresConfirmation(prefixedName),
                    };
                }
            }

            // Get internal tools with prefixing
            if (this.config.enableInternalTools) {
                const internalTools = this.internalToolManager.getAllTools();
                
                for (const [originalName, tool] of Object.entries(internalTools)) {
                    // Skip if tool shouldn't be exposed in current mode
                    if (!this.shouldExposeInternalTool(tool, originalName)) {
                        continue;
                    }

                    const prefixedName = this.applyPrefix(originalName, 'internal');
                    
                    combinedTools[prefixedName] = {
                        description: tool.description,
                        parameters: tool.parameters,
                        source: 'internal',
                        originalName,
                        prefixed: true,
                        requiresConfirmation: await this.requiresConfirmation(prefixedName),
                    };
                }
            }

            // Cache the results
            this.toolCache.set('allTools', combinedTools);
            this.lastCacheUpdate = now;

            if (!this.toolsAlreadyLogged) {
                this.logAvailableTools(combinedTools);
                this.toolsAlreadyLogged = true;
            }

            return combinedTools;
        } catch (error) {
            logger.error('UnifiedToolManager: Failed to get all tools', { error });
            throw error;
        }
    }

    /**
     * Execute a tool with enhanced security and confirmation
     */
    async executeTool(toolName: string, args: any, sessionId?: string): Promise<ToolExecutionResult> {
        if (!this.initialized) {
            await this.initialize();
        }

        const executionId = uuidv4();
        const startTime = Date.now();

        try {
            // Resolve tool name and source
            const { originalName, source } = this.resolveToolName(toolName);

            // Create execution details for confirmation
            const details: ToolExecutionDetails = {
                toolName: originalName,
                description: await this.getToolDescription(originalName, source),
                arguments: args,
                source,
                sessionId,
                timestamp: startTime,
                executionId,
            };

            // Request confirmation
            const confirmationResult = await this.requestToolConfirmation(details);
            
            if (!confirmationResult.approved) {
                throw new ToolNotAllowedError(originalName, sessionId, {
                    reason: 'User denied confirmation or tool not allowed',
                    confirmationResult
                });
            }

            // Execute the tool
            let result: ToolExecutionResult;

            if (source === 'internal' && this.config.enableInternalTools) {
                if (!this.internalToolManager.isInternalTool(originalName)) {
                    throw new ToolNotFoundError(originalName, 'internal');
                }
                result = await this.internalToolManager.executeTool(originalName, args);
            } else if (source === 'mcp' && this.config.enableMcpTools) {
                result = await this.mcpManager.executeTool(originalName, args);
            } else {
                throw new ToolNotFoundError(originalName, source);
            }

            // Emit execution completed event
            if (this.eventManager && sessionId) {
                this.eventManager.emitSessionEvent(sessionId, SessionEvents.TOOL_EXECUTION_COMPLETED, {
                    toolName: originalName,
                    toolType: source,
                    sessionId,
                    executionId,
                    duration: Date.now() - startTime,
                    success: true,
                    result,
                    confirmationResult,
                    timestamp: Date.now(),
                });
            }

            return result;
        } catch (error) {
            const duration = Date.now() - startTime;
            const errorMessage = error instanceof Error ? error.message : String(error);

            // Emit execution failed event
            if (this.eventManager && sessionId) {
                this.eventManager.emitSessionEvent(sessionId, SessionEvents.TOOL_EXECUTION_FAILED, {
                    toolName,
                    sessionId,
                    executionId,
                    error: errorMessage,
                    duration,
                    timestamp: Date.now(),
                });
            }

            logger.error(`UnifiedToolManager: Tool execution failed for '${toolName}'`, {
                toolName,
                error: errorMessage,
                sessionId,
                executionId,
                duration,
            });

            throw new ToolExecutionError(toolName, errorMessage, error instanceof Error ? error : undefined, {
                sessionId,
                executionId,
                duration
            });
        }
    }

    /**
     * Get tools formatted for specific LLM providers
     */
    async getToolsForProvider(
        provider: 'openai' | 'anthropic' | 'openrouter' | 'aws' | 'azure' | 'qwen' | 'gemini'
    ): Promise<any[]> {
        const allTools = await this.getAllTools();
        return SchemaConverter.convertForProvider(allTools, provider);
    }

    /**
     * Handle tool confirmation response from UI
     */
    async handleConfirmationResponse(response: any): Promise<void> {
        if (this.confirmationProvider?.handleConfirmationResponse) {
            await this.confirmationProvider.handleConfirmationResponse(response);
        }
    }

    /**
     * Get pending confirmations for UI display
     */
    getPendingConfirmations(): ToolExecutionDetails[] {
        if (this.confirmationProvider && 'getPendingConfirmations' in this.confirmationProvider) {
            return (this.confirmationProvider as any).getPendingConfirmations();
        }
        return [];
    }

    /**
     * Get enhanced manager statistics
     */
    getStats(): any {
        return {
            initialized: this.initialized,
            cacheStats: {
                size: this.toolCache.size,
                lastUpdate: this.lastCacheUpdate,
                cacheTimeout: this.cacheTimeout,
            },
            internalTools: this.config.enableInternalTools ? this.internalToolManager.getManagerStats() : null,
            mcpTools: this.config.enableMcpTools ? {
                clientCount: this.mcpManager.getClients().size,
                failedConnections: Object.keys(this.mcpManager.getFailedConnections()).length,
            } : null,
            confirmation: this.confirmationProvider ? {
                pendingConfirmations: this.getPendingConfirmations().length,
                config: this.config.confirmation,
            } : null,
            config: this.config,
        };
    }

    /**
     * Clear tool cache
     */
    clearCache(): void {
        this.toolCache.clear();
        this.lastCacheUpdate = 0;
        logger.debug('UnifiedToolManager: Tool cache cleared');
    }

    // Private helper methods

    /**
     * Apply prefix to tool name
     */
    private applyPrefix(toolName: string, source: 'mcp' | 'internal'): string {
        // Check for legacy cipher_ prefix and maintain backward compatibility
        if (toolName.startsWith(this.config.prefixing.legacyPrefix)) {
            return toolName; // Keep legacy prefix as-is
        }

        const prefix = source === 'mcp' ? this.config.prefixing.mcpPrefix : this.config.prefixing.internalPrefix;
        return `${prefix}${toolName}`;
    }

    /**
     * Resolve tool name and determine source
     */
    private resolveToolName(toolName: string): { originalName: string; source: 'mcp' | 'internal' } {
        // Check for legacy cipher_ prefix
        if (toolName.startsWith(this.config.prefixing.legacyPrefix)) {
            return {
                originalName: toolName.substring(this.config.prefixing.legacyPrefix.length),
                source: 'internal'
            };
        }

        // Check for MCP prefix
        if (toolName.startsWith(this.config.prefixing.mcpPrefix)) {
            return {
                originalName: toolName.substring(this.config.prefixing.mcpPrefix.length),
                source: 'mcp'
            };
        }

        // Check for internal prefix
        if (toolName.startsWith(this.config.prefixing.internalPrefix)) {
            return {
                originalName: toolName.substring(this.config.prefixing.internalPrefix.length),
                source: 'internal'
            };
        }

        // No prefix - assume internal for backward compatibility
        return {
            originalName: toolName,
            source: 'internal'
        };
    }

    /**
     * Get tool description for confirmation dialog
     */
    private async getToolDescription(toolName: string, source: 'mcp' | 'internal'): Promise<string> {
        try {
            if (source === 'internal') {
                const tools = this.internalToolManager.getAllTools();
                return tools[toolName]?.description || 'No description available';
            } else {
                const tools = await this.mcpManager.getAllTools();
                return tools[toolName]?.description || 'No description available';
            }
        } catch {
            return 'Description unavailable';
        }
    }

    /**
     * Request tool confirmation
     */
    private async requestToolConfirmation(details: ToolExecutionDetails): Promise<ToolConfirmationResult> {
        if (!this.confirmationProvider) {
            // If no confirmation provider, default to approved
            return {
                approved: true,
                preApproved: true,
                method: 'pre-approved',
                confirmationTime: 0,
            };
        }

        // Check if tool requires confirmation based on source
        const requiresConfirmation = (details.source === 'mcp' && this.config.confirmation.requireConfirmationForMcp) ||
                                    (details.source === 'internal' && this.config.confirmation.requireConfirmationForInternal);

        if (!requiresConfirmation) {
            return {
                approved: true,
                preApproved: true,
                method: 'pre-approved',
                confirmationTime: 0,
            };
        }

        const startTime = Date.now();
        const approved = await this.confirmationProvider.requestConfirmation(details);
        
        return {
            approved,
            preApproved: false,
            method: 'user-confirmation',
            confirmationTime: Date.now() - startTime,
        };
    }

    /**
     * Check if tool requires confirmation
     */
    private async requiresConfirmation(toolName: string): Promise<boolean> {
        if (!this.confirmationProvider) {
            return false;
        }

        const isAllowed = await this.confirmationProvider.allowedToolsProvider.isToolAllowed(toolName);
        return !isAllowed;
    }

    /**
     * Check if MCP tools should be exposed based on mode
     */
    private shouldExposeMcpTools(): boolean {
        return this.config.mode === 'cli' || 
               this.config.mode === 'aggregator' || 
               this.config.mode === 'api' ||
               this.config.mode === 'default';
    }

    /**
     * Check if internal tool should be exposed based on mode
     */
    private shouldExposeInternalTool(tool: any, toolName: string): boolean {
        if (this.config.mode === 'cli') {
            // CLI mode: Only search tools accessible to LLM
            const isSearchTool = toolName.includes('search') || 
                                toolName.includes('memory_') || 
                                toolName.includes('knowledge_');
            return isSearchTool && tool.agentAccessible !== false;
        } else if (this.config.mode === 'aggregator') {
            // Aggregator mode: All tools available
            return true;
        } else {
            // Default/API modes: Only agent-accessible tools
            return tool.agentAccessible !== false;
        }
    }

    /**
     * Log available tools for debugging
     */
    private logAvailableTools(tools: CombinedToolSet): void {
        const toolsBySource = {
            mcp: Object.entries(tools).filter(([_, tool]) => tool.source === 'mcp'),
            internal: Object.entries(tools).filter(([_, tool]) => tool.source === 'internal'),
        };

        logger.info('UnifiedToolManager: Available tools:', {
            total: Object.keys(tools).length,
            mcp: toolsBySource.mcp.length,
            internal: toolsBySource.internal.length,
            mode: this.config.mode,
            securityEnabled: !!this.confirmationProvider,
        });

        if (logger.level === 'debug') {
            logger.debug('UnifiedToolManager: Tool details:', {
                mcpTools: toolsBySource.mcp.map(([name, tool]) => ({ 
                    name, 
                    originalName: tool.originalName,
                    requiresConfirmation: tool.requiresConfirmation 
                })),
                internalTools: toolsBySource.internal.map(([name, tool]) => ({ 
                    name, 
                    originalName: tool.originalName,
                    requiresConfirmation: tool.requiresConfirmation 
                })),
            });
        }
    }

	async getToolsForProvider(
		provider:
			| 'openai'
			| 'anthropic'
			| 'openrouter'
			| 'aws'
			| 'azure'
			| 'qwen'
			| 'gemini'
			| 'deepseek'
	): Promise<any[]> {
		logger.info(`UnifiedToolManager: Getting tools for provider: ${provider}`);
		const allTools = await this.getAllTools();
		logger.info(`UnifiedToolManager: Got ${Object.keys(allTools).length} total tools`);

		switch (provider) {
			case 'openai':
			case 'openrouter':
				logger.info('UnifiedToolManager: Formatting tools for OpenAI');
				return this.formatToolsForOpenAI(allTools);
			case 'qwen':
				return this.formatToolsForOpenAI(allTools);
			case 'gemini':
				logger.info('UnifiedToolManager: Formatting tools for Gemini');
				return this.formatToolsForGemini(allTools);
			case 'anthropic':
				logger.info('UnifiedToolManager: Formatting tools for Anthropic');
				return this.formatToolsForAnthropic(allTools);
			case 'aws':
				logger.info('UnifiedToolManager: Formatting tools for AWS (Anthropic-compatible)');
				return this.formatToolsForAnthropic(allTools); // AWS Bedrock uses Anthropic-compatible format
			case 'azure':
				logger.info('UnifiedToolManager: Formatting tools for Azure (OpenAI-compatible)');
				return this.formatToolsForOpenAI(allTools); // Azure OpenAI uses OpenAI-compatible format
			case 'deepseek':
				logger.info('UnifiedToolManager: Formatting tools for Deepseek');
				return this.formatToolsForOpenAI(allTools); // Deepseek uses OpenAI-compatible format
			default:
				throw new Error(`Unsupported provider: ${provider}`);
		}
	}

        try {
            logger.info('UnifiedToolManager: Shutting down...');

            // Clear cache
            this.clearCache();

            // Clear pending confirmations
            if (this.confirmationProvider && 'clearPendingConfirmations' in this.confirmationProvider) {
                (this.confirmationProvider as any).clearPendingConfirmations();
            }

            // Close storage connections if any
            if (this.confirmationProvider?.allowedToolsProvider && 'close' in this.confirmationProvider.allowedToolsProvider) {
                (this.confirmationProvider.allowedToolsProvider as any).close();
            }

            this.initialized = false;
            logger.info('UnifiedToolManager: Shutdown completed');
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : String(error);
            logger.error(`UnifiedToolManager: Shutdown failed: ${errorMessage}`);
            throw error;
        }
    }
}