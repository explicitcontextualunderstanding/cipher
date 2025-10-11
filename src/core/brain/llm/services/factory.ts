import { MCPManager } from '../../../mcp/manager.js';
import { UnifiedToolManager } from '../../tools/unified-tool-manager.js';
import { ContextManager } from '../messages/manager.js';
import { LLMConfig } from '../config.js';
import { ILLMService } from './types.js';
import { env } from '../../../env.js';
import { logger } from '../../../logger/index.js';
import { OpenAIService } from './openai.js';
import { AnthropicService } from './anthropic.js';
import { OpenRouterService } from './openrouter.js';
import { OllamaService } from './ollama.js';
import { QwenService, QwenOptions } from './qwen.js';
import { AwsService } from './aws.js';
import { AzureService } from './azure.js';
import { GeminiService } from './gemini.js';
import { LMStudioService } from './lmstudio.js';
import { DeepseekService } from './deepseek.js';

function extractApiKey(config: LLMConfig): string {
    const provider = config.provider.toLowerCase();

    // These providers don't require traditional API keys
    if (
    if (provider === 'deepseek') {
        return 'https://api.deepseek.com';
    }

    return '';
}

function _createLLMService(
    config: LLMConfig,
    mcpManager: MCPManager,
    contextManager: ContextManager,
    unifiedToolManager?: UnifiedToolManager,
    eventManager?: EventManager
): ILLMService {
    // Validate API key (or allow providers that don't require them)
    const apiKey = extractApiKey(config);
    const baseURL = getOpenAICompatibleBaseURL(config);

    // Build a unified config that the generic LLMServices wrapper
    // can consume. This keeps provider-specific wiring inside the
    // LLMServices implementation and avoids fragile switch logic
    // in the factory.
    const unifiedConfig: ExtendedLLMConfig = {
        provider: (config.provider || '').toLowerCase() as any,
        model: config.model,
        apiKey: apiKey !== 'not-required' ? apiKey : undefined,
        baseURL: baseURL || undefined,
        maxIterations: config.maxIterations,
        streaming: false,
        awsConfig: (config as any).aws,
        region: (config as any).aws?.region || process.env.AWS_DEFAULT_REGION,
        endpoint: (config as any).azure?.endpoint || process.env.AZURE_OPENAI_ENDPOINT,
        deployment: (config as any).azure?.deployment,
        apiVersion: (config as any).azure?.apiVersion,
        resourceName: (config as any).azure?.resourceName,
        enableThinking: (config as any).qwenOptions?.enableThinking,
        thinkingBudget: (config as any).qwenOptions?.thinkingBudget,
    };

    // Defer to the generic LLMServices implementation which knows
    // how to initialize provider-specific clients.
    return new LLMServices(unifiedConfig, mcpManager, contextManager, unifiedToolManager, eventManager);
}

export function createLLMService(
    config: LLMConfig,
    mcpManager: MCPManager,
    contextManager: ContextManager,
    unifiedToolManager?: UnifiedToolManager,
    eventManager?: EventManager
): ILLMService {
    logger.info(`Creating LLM service for provider: ${config.provider}`, {
        model: config.model,
        hasUnifiedToolManager: !!unifiedToolManager,
        hasEventManager: !!eventManager,
    });

    const service = _createLLMService(config, mcpManager, contextManager, unifiedToolManager, eventManager);

    // Configure token-aware compression for the context manager
    configureCompressionForService(config, contextManager);

    logger.info(`Successfully created unified LLM service for ${config.provider}`, {
        model: config.model,
        provider: config.provider,
    });

    return service;
}
				config.model,
				mcpManager,
				contextManager,
				config.maxIterations,
				qwenOptions,
				unifiedToolManager
			);
		}
		case 'gemini': {
			logger.debug('Creating Gemini service', { model: config.model, hasApiKey: !!apiKey });
			try {
				return new GeminiService(
					apiKey,
					config.model,
					mcpManager,
					contextManager,
					config.maxIterations,
					unifiedToolManager
				);
			} catch (error) {
				logger.error('Failed to create Gemini service', {
					error: error instanceof Error ? error.message : String(error),
					model: config.model,
				});
				throw error;
			}
		}
		case 'deepseek': {
			const baseURL = getOpenAICompatibleBaseURL(config);
			const OpenAIClass = require('openai');
			const openai = new OpenAIClass({ apiKey, baseURL });
			return new DeepseekService(
				openai,
				config.model,
				mcpManager,
				contextManager,
				config.maxIterations,
				unifiedToolManager
			);
		}
		default:
			throw new Error(`Unsupported LLM provider: ${config.provider}`);
	}
}

export function createLLMService(
    config: LLMConfig,
    mcpManager: MCPManager,
    contextManager: ContextManager,
    unifiedToolManager?: UnifiedToolManager,
    eventManager?: EventManager
): ILLMService {
    logger.info(`Creating LLM service for provider: ${config.provider}`, {
        model: config.model,
        hasUnifiedToolManager: !!unifiedToolManager,
        hasEventManager: !!eventManager,
    });

    const service = _createLLMService(
        config, 
        mcpManager, 
        contextManager, 
        unifiedToolManager, 
        eventManager
    );

    // Configure token-aware compression for the context manager
    configureCompressionForService(config, contextManager);

    logger.info(`Successfully created unified LLM service for ${config.provider}`, {
        model: config.model,
        provider: config.provider,
    });

    return service;
}

/**
 * Configure compression settings for the context manager based on LLM config
 */
async function configureCompressionForService(
    config: LLMConfig,
    contextManager: ContextManager
): Promise<void> {
    try {
        // Extract provider and model info
        const provider = config.provider.toLowerCase();
        const model = config.model;

        // Get context window size from defaults since it's not in config
        const contextWindow = getDefaultContextWindow(provider, model);

        // Configure compression asynchronously to avoid blocking service creation
        setImmediate(async () => {
            try {
                await contextManager.configureCompression(provider, model, contextWindow);
                logger.debug('Token-aware compression configured for LLM service', {
                    provider,
                    model,
                    contextWindow,
                });
            } catch (error) {
                logger.warn('Failed to configure compression for LLM service', {
                    error: (error as Error).message,
                    provider,
                    model,
                });
            }
        });
    } catch (error) {
        logger.error('Error in compression configuration', { error });
    }
}

/**
 * Get default context window size for provider/model combinations
 */
function getDefaultContextWindow(provider: string, model?: string): number {
	const defaults: Record<string, Record<string, number>> = {
		openai: {
			'gpt-3.5-turbo': 16385,
			'gpt-4': 8192,
			'gpt-4-32k': 32768,
			'gpt-4-turbo': 128000,
			'gpt-4o': 128000,
			'gpt-4o-mini': 128000,
			'o1-preview': 128000,
			'o1-mini': 128000,
			default: 8192,
		},
		anthropic: {
			'claude-3-opus': 200000,
			'claude-3-sonnet': 200000,
			'claude-3-haiku': 200000,
			'claude-3-5-sonnet': 200000,
			'claude-2.1': 200000,
			'claude-2.0': 100000,
			'claude-instant-1.2': 100000,
			default: 200000,
		},
		gemini: {
			'gemini-pro': 32760,
			'gemini-pro-vision': 16384,
			'gemini-ultra': 32760,
			'gemini-1.5-pro': 1000000,
			'gemini-1.5-flash': 1000000,
			'gemini-1.5-pro-latest': 2000000,
			'gemini-1.5-flash-latest': 1000000,
			'gemini-2.0-flash': 1000000,
			'gemini-2.0-flash-exp': 1000000,
			'gemini-2.5-pro': 2000000,
			'gemini-2.5-flash': 1000000,
			'gemini-2.5-flash-lite': 1000000,
			default: 1000000,
		},
		deepseek: {
			default: 128000,
		},
		ollama: {
			default: 8192, // Conservative default for local models
		},
		openrouter: {
			default: 8192, // Varies by model, conservative default
		},
	};

    const providerDefaults = defaults[provider];
    if (!providerDefaults) {
        return 8192; // Global fallback
    }

    return providerDefaults[model || 'default'] || providerDefaults.default || 8192;
}