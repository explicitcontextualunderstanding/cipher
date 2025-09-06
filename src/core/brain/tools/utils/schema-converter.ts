/**
 * Schema Converter Utility
 * 
 * Converts tool schemas between different LLM provider formats.
 */

import { logger } from '../../../../logger/index.js';
import { CombinedToolSet } from '../unified-tool-manager.js';

/**
 * Tool schema conversion utilities
 */
export class SchemaConverter {
	/**
	 * Convert tools to OpenAI/OpenRouter format
	 */
	static toOpenAIFormat(tools: CombinedToolSet): any[] {
		return Object.entries(tools).map(([name, tool]) => ({
			type: 'function',
			function: {
				name,
				description: tool.description,
				parameters: tool.parameters,
			},
		}));
	}

	/**
	 * Convert tools to Anthropic format
	 */
	static toAnthropicFormat(tools: CombinedToolSet): any[] {
		return Object.entries(tools).map(([name, tool]) => ({
			name,
			description: tool.description,
			input_schema: tool.parameters,
		}));
	}

	/**
	 * Convert tools to Gemini format (same as OpenAI)
	 */
	static toGeminiFormat(tools: CombinedToolSet): any[] {
		return this.toOpenAIFormat(tools);
	}

	/**
	 * Convert tools to AWS Bedrock format (Anthropic-compatible)
	 */
	static toAWSFormat(tools: CombinedToolSet): any[] {
		return this.toAnthropicFormat(tools);
	}

	/**
	 * Convert tools to Azure OpenAI format (OpenAI-compatible)
	 */
	static toAzureFormat(tools: CombinedToolSet): any[] {
		return this.toOpenAIFormat(tools);
	}

	/**
	 * Convert tools to Qwen format (OpenAI-compatible)
	 */
	static toQwenFormat(tools: CombinedToolSet): any[] {
		return this.toOpenAIFormat(tools);
	}

	/**
	 * Convert tools for a specific provider
	 */
	static convertForProvider(
		tools: CombinedToolSet,
		provider: 'openai' | 'anthropic' | 'openrouter' | 'aws' | 'azure' | 'qwen' | 'gemini'
	): any[] {
		logger.debug(`SchemaConverter: Converting tools for provider: ${provider}`);

		switch (provider) {
			case 'openai':
			case 'openrouter':
				return this.toOpenAIFormat(tools);
			case 'qwen':
				return this.toQwenFormat(tools);
			case 'gemini':
				return this.toGeminiFormat(tools);
			case 'anthropic':
				return this.toAnthropicFormat(tools);
			case 'aws':
				return this.toAWSFormat(tools);
			case 'azure':
				return this.toAzureFormat(tools);
			default:
				throw new Error(`Unsupported provider: ${provider}`);
		}
	}

	/**
	 * Validate tool schema
	 */
	static validateToolSchema(tool: any): boolean {
		try {
			// Check required fields
			if (!tool.name || typeof tool.name !== 'string') {
				return false;
			}
			if (!tool.description || typeof tool.description !== 'string') {
				return false;
			}
			if (!tool.parameters || typeof tool.parameters !== 'object') {
				return false;
			}

			// Validate parameters schema
			if (!this.validateParametersSchema(tool.parameters)) {
				return false;
			}

			return true;
		} catch (error) {
			logger.error('SchemaConverter: Tool schema validation failed', { error, tool });
			return false;
		}
	}

	/**
	 * Validate parameters schema
	 */
	private static validateParametersSchema(parameters: any): boolean {
		try {
			// Check if it's a valid JSON schema
			if (parameters.type !== 'object') {
				return false;
			}

			// Validate properties if present
			if (parameters.properties) {
				if (typeof parameters.properties !== 'object') {
					return false;
				}

				// Validate each property
				for (const [propName, propSchema] of Object.entries(parameters.properties)) {
					if (!this.validatePropertySchema(propName, propSchema as any)) {
						return false;
					}
				}
			}

			// Validate required array if present
			if (parameters.required) {
				if (!Array.isArray(parameters.required)) {
					return false;
				}
			}

			return true;
		} catch (error) {
			logger.error('SchemaConverter: Parameters schema validation failed', { error, parameters });
			return false;
		}
	}

	/**
	 * Validate property schema
	 */
	private static validatePropertySchema(propName: string, propSchema: any): boolean {
		try {
			// Check required fields
			if (!propSchema.type) {
				return false;
			}

			// Validate type
			const validTypes = ['string', 'number', 'integer', 'boolean', 'array', 'object'];
			if (!validTypes.includes(propSchema.type)) {
				return false;
			}

			// Validate description if present
			if (propSchema.description && typeof propSchema.description !== 'string') {
				return false;
			}

			// Validate enum if present
			if (propSchema.enum && !Array.isArray(propSchema.enum)) {
				return false;
			}

			// Validate items for array types
			if (propSchema.type === 'array' && propSchema.items) {
				if (!this.validatePropertySchema(`${propName}.items`, propSchema.items)) {
					return false;
				}
			}

			// Validate properties for object types
			if (propSchema.type === 'object' && propSchema.properties) {
				if (typeof propSchema.properties !== 'object') {
					return false;
				}
			}

			return true;
		} catch (error) {
			logger.error('SchemaConverter: Property schema validation failed', { 
				error, 
				propName, 
				propSchema 
			});
			return false;
		}
	}

	/**
	 * Normalize tool schema
	 */
	static normalizeToolSchema(tool: any): any {
		try {
			const normalized = {
				name: tool.name,
				description: tool.description || '',
				parameters: this.normalizeParametersSchema(tool.parameters || {})
			};

			// Validate normalized schema
			if (!this.validateToolSchema(normalized)) {
				throw new Error('Normalized tool schema is invalid');
			}

			return normalized;
		} catch (error) {
			logger.error('SchemaConverter: Tool schema normalization failed', { error, tool });
			throw error;
		}
	}

	/**
	 * Normalize parameters schema
	 */
	private static normalizeParametersSchema(parameters: any): any {
		// Ensure type is object
		if (!parameters.type) {
			parameters.type = 'object';
		}

		// Ensure properties object exists
		if (!parameters.properties) {
			parameters.properties = {};
		}

		// Ensure required array exists
		if (!parameters.required) {
			parameters.required = [];
		}

		return parameters;
	}

	/**
	 * Get supported providers
	 */
	static getSupportedProviders(): string[] {
		return ['openai', 'anthropic', 'openrouter', 'aws', 'azure', 'qwen', 'gemini'];
	}

	/**
	 * Check if provider is supported
	 */
	static isProviderSupported(provider: string): boolean {
		return this.getSupportedProviders().includes(provider);
	}
}
