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
        provider === 'ollama' ||
        provider === 'lmstudio' ||
        provider === 'aws' ||
        provider === 'azure'
    ) {
        return 'not-required';
    }

    // Get API key from config (already expanded)
    let apiKey = config.apiKey || '';

    if (!apiKey) {
        const errorMsg = `Error: API key for ${provider} not found`;
        logger.error(errorMsg);
        logger.error(`Please set your ${provider} API key in the config file or .env file`);
        throw new Error(errorMsg);
    }
    logger.debug('Verified API key');
    return apiKey;
}

function getOpenAICompatibleBaseURL(llmConfig: LLMConfig): string {
    if (llmConfig.baseURL) {
        let baseUrl = llmConfig.baseURL.replace(/\/$/, '');

        // For Ollama, ensure /v1 suffix for OpenAI-compatible endpoint
        const provider = llmConfig.provider.toLowerCase();
        if (provider === 'ollama' && !baseUrl.endsWith('/v1') && !baseUrl.endsWith('/api')) {
            baseUrl = baseUrl + '/v1';
        }

        return baseUrl;
    }

    // Provider-specific defaults and environment fallbacks
    const provider = llmConfig.provider.toLowerCase();

    if (provider === 'openrouter') {
        return 'https://openrouter.ai/api/v1';
    }

    if (provider === 'ollama') {
        // Use environment variable if set, otherwise default to localhost:11434/v1
        let baseUrl = env.OLLAMA_BASE_URL || 'http://localhost:11434/v1';
        // Ensure /v1 suffix for OpenAI-compatible endpoint
        if (!baseUrl.endsWith('/v1') && !baseUrl.endsWith('/api')) {
            baseUrl = baseUrl.replace(/\/$/, '') + '/v1';
        }

        return baseUrl;
    }

    if (provider === 'lmstudio') {
        // Use environment variable if set, otherwise default to localhost:1234/v1
        return env.LMSTUDIO_BASE_URL || 'http://localhost:1234/v1';
    }

    if (provider === 'qwen') {
        return llmConfig.baseURL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    }

    // TODO: Consider if this is necessary
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
    // Extract and validate API key
    const apiKey = extractApiKey(config);
    const baseURL = getOpenAICompatibleBaseURL(config);
    const providerType = mapProviderToUnifiedType(config.provider);

    // Create unified configuration
    const unifiedConfig: ExtendedLLMConfig = {
        provider: providerType,
        model: config.model,
        apiKey: apiKey !== 'not-required' ? apiKey : undefined,
        baseURL: baseURL || undefined,
        maxIterations: config.maxIterations,
        streaming: false, // Can be made configurable
    };

    // Add provider-specific configurations
    switch (providerType) {
        case 'aws':
            unifiedConfig.region = config.aws?.region || process.env.AWS_DEFAULT_REGION || 'us-east-1';
            unifiedConfig.awsConfig = config.aws;
            unifiedConfig.inferenceProfileArn = config.aws?.inferenceProfileArn;
            break;

        case 'azure':
            unifiedConfig.endpoint = config.azure?.endpoint || process.env.AZURE_OPENAI_ENDPOINT;
            unifiedConfig.deployment = config.azure?.deployment;
            unifiedConfig.apiVersion = config.azure?.apiVersion;
            unifiedConfig.resourceName = config.azure?.resourceName;
            break;

        case 'qwen':
            unifiedConfig.enableThinking = config.qwenOptions?.enableThinking;
            unifiedConfig.thinkingBudget = config.qwenOptions?.thinkingBudget;
            break;

        case 'openrouter':
            unifiedConfig.baseURL = 'https://openrouter.ai/api/v1';
            break;

        case 'ollama':
        case 'lmstudio':
        case 'vllm':
            // baseURL already set above
            break;
    }

    // Provider instantiation that needs direct client objects or
    // special handling
    switch (providerType) {
        case 'qwen': {
            const OpenAIClass = require('openai');
            const openai = new OpenAIClass({ apiKey, baseURL });
            const qwenOptions: QwenOptions = {
                ...(config.qwenOptions?.enableThinking !== undefined && { enableThinking: config.qwenOptions.enableThinking }),
                ...(config.qwenOptions?.thinkingBudget !== undefined && { thinkingBudget: config.qwenOptions.thinkingBudget }),
                ...(config.qwenOptions?.temperature !== undefined && { temperature: config.qwenOptions.temperature }),
                ...(config.qwenOptions?.top_p !== undefined && { top_p: config.qwenOptions.top_p }),
            };
            return new QwenService(
                openai,
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
                logger.error('Failed to create Gemini service', { error: error instanceof Error ? error.message : String(error), model: config.model });
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

        // Get context window size from defaults
        const contextWindow = getDefaultContextWindow(provider, model);

        setImmediate(async () => {
            try {
                await contextManager.configureCompression(provider, model, contextWindow);
                logger.debug('Token-aware compression configured for LLM service', { provider, model, contextWindow });
            } catch (error) {
                logger.warn('Failed to configure compression for LLM service', { error: (error as Error).message, provider, model });
            }
        });
    } catch (error) {
        logger.error('Error in compression configuration', { error });
    }
}

function getDefaultContextWindow(provider: string, model?: string): number {
    const defaults: Record<string, Record<string, number>> = {
        openai: { default: 8192 },
        anthropic: { default: 200000 },
        gemini: { default: 1000000 },
        deepseek: { default: 128000 },
        ollama: { default: 8192 },
        openrouter: { default: 8192 },
    };

    const providerDefaults = defaults[provider];
    if (!providerDefaults) return 8192;
    return providerDefaults[model || 'default'] || providerDefaults.default || 8192;
}
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
        provider === 'ollama' ||
        provider === 'lmstudio' ||
        provider === 'aws' ||
        provider === 'azure'
    ) {
        return 'not-required';
    }

    // Get API key from config (already expanded)
    let apiKey = config.apiKey || '';

    if (!apiKey) {
        const errorMsg = `Error: API key for ${provider} not found`;
        logger.error(errorMsg);
        logger.error(`Please set your ${provider} API key in the config file or .env file`);
        throw new Error(errorMsg);
    }
    logger.debug('Verified API key');
    return apiKey;
}

function getOpenAICompatibleBaseURL(llmConfig: LLMConfig): string {
    if (llmConfig.baseURL) {
        let baseUrl = llmConfig.baseURL.replace(/\/$/, '');

        // For Ollama, ensure /v1 suffix for OpenAI-compatible endpoint
        const provider = llmConfig.provider.toLowerCase();
        if (provider === 'ollama' && !baseUrl.endsWith('/v1') && !baseUrl.endsWith('/api')) {
            baseUrl = baseUrl + '/v1';
        }

        return baseUrl;
    }

    // Provider-specific defaults and environment fallbacks
    const provider = llmConfig.provider.toLowerCase();

    if (provider === 'openrouter') {
        return 'https://openrouter.ai/api/v1';
    }

    if (provider === 'ollama') {
        // Use environment variable if set, otherwise default to localhost:11434/v1
        let baseUrl = env.OLLAMA_BASE_URL || 'http://localhost:11434/v1';

        // Ensure /v1 suffix for OpenAI-compatible endpoint
        if (!baseUrl.endsWith('/v1') && !baseUrl.endsWith('/api')) {
            baseUrl = baseUrl.replace(/\/$/, '') + '/v1';
        }

        return baseUrl;
    }

    if (provider === 'lmstudio') {
        // Use environment variable if set, otherwise default to localhost:1234/v1
        return env.LMSTUDIO_BASE_URL || 'http://localhost:1234/v1';
    }

    if (provider === 'qwen') {
        return llmConfig.baseURL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    }

	// TODO: Consider if this is necessary
	if (provider === 'deepseek') {
		return 'https://api.deepseek.com';
	}

	return '';
import { LLMServices, ExtendedLLMConfig } from './service.js';

function extractApiKey(config: LLMConfig): string {
    const provider = (config.provider || '').toLowerCase();

    // Providers that don't require an API key
    if (provider === 'ollama' || provider === 'lmstudio' || provider === 'aws' || provider === 'azure') {
        return 'not-required';
    }

    const apiKey = config.apiKey || '';
    if (!apiKey) {
        const msg = `Error: API key for ${provider} not found`;
        logger.error(msg);
        logger.error(`Please set your ${provider} API key in the config file or .env file`);
        throw new Error(msg);
    }
    logger.debug('Verified API key', { provider });
    return apiKey;
}

function getOpenAICompatibleBaseURL(llmConfig: LLMConfig): string {
    if (llmConfig.baseURL) {
        let baseUrl = llmConfig.baseURL.replace(/\/$/, '');
        const provider = (llmConfig.provider || '').toLowerCase();
        if (provider === 'ollama' && !baseUrl.endsWith('/v1') && !baseUrl.endsWith('/api')) {
            baseUrl = `${baseUrl}/v1`;
        }
        return baseUrl;
    }

    const provider = (llmConfig.provider || '').toLowerCase();
    if (provider === 'openrouter') return 'https://openrouter.ai/api/v1';
    if (provider === 'ollama') return env.OLLAMA_BASE_URL || 'http://localhost:11434/v1';
    if (provider === 'lmstudio') return env.LMSTUDIO_BASE_URL || 'http://localhost:1234/v1';
    if (provider === 'qwen') return llmConfig.baseURL || 'https://dashscope.aliyuncs.com/compatible-mode/v1';
    if (provider === 'deepseek') return 'https://api.deepseek.com';
    return '';
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

    const apiKey = extractApiKey(config);
    const baseURL = getOpenAICompatibleBaseURL(config);

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

    const service = new LLMServices(unifiedConfig, mcpManager, contextManager, unifiedToolManager, eventManager);

    // Configure token-aware compression for context manager asynchronously
    setImmediate(async () => {
        try {
            await contextManager.configureCompression(unifiedConfig.provider as string, unifiedConfig.model, getDefaultContextWindow(unifiedConfig.provider as string, unifiedConfig.model));
            logger.debug('Token-aware compression configured for LLM service', { provider: unifiedConfig.provider, model: unifiedConfig.model });
        } catch (err) {
            logger.warn('Failed to configure compression for LLM service', { error: (err as Error).message, provider: unifiedConfig.provider, model: unifiedConfig.model });
        }
    });

    logger.info(`Successfully created unified LLM service for ${config.provider}`, { model: config.model, provider: config.provider });
    return service;
}

function getDefaultContextWindow(provider: string, model?: string): number {
    const defaults: Record<string, Record<string, number>> = {
        openai: { default: 8192 },
        anthropic: { default: 200000 },
        gemini: { default: 1000000 },
        deepseek: { default: 128000 },
        ollama: { default: 8192 },
        openrouter: { default: 8192 },
    };
    const d = defaults[provider] || { default: 8192 };
    return d[model || 'default'] || d.default || 8192;
}
}