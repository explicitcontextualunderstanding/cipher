/**
 * Internal Tools Provider with Service Injection
 * 
 * Enhanced internal tools provider with dependency injection and service registry.
 */

import { logger } from '../../../../logger/index.js';
import { InternalTool, InternalToolContext, InternalToolSet } from '../types.js';
import { ToolServiceInjectionError } from '../errors/tool-errors.js';

/**
 * Services available for injection into internal tools
 */
export interface InternalToolsServices {
	embeddingManager?: any;
	vectorStoreManager?: any;
	llmService?: any;
	knowledgeGraphManager?: any;
	sessionManager?: any;
	fileService?: any;
	eventManager?: any;
}

/**
 * Service registry for managing available services
 */
export class ServiceRegistry {
	private services: InternalToolsServices = {};
	private initialized = false;

	/**
	 * Register services
	 */
	registerServices(services: Partial<InternalToolsServices>): void {
		this.services = { ...this.services, ...services };
		this.initialized = true;
		logger.debug('ServiceRegistry: Registered services', { 
			serviceNames: Object.keys(services) 
		});
	}

	/**
	 * Get a specific service
	 */
	getService<T extends keyof InternalToolsServices>(serviceName: T): InternalToolsServices[T] {
		if (!this.initialized) {
			throw new ToolServiceInjectionError(
				serviceName,
				'unknown',
				'Service registry not initialized'
			);
		}

		const service = this.services[serviceName];
		if (!service) {
			throw new ToolServiceInjectionError(
				serviceName,
				'unknown',
				`Service '${serviceName}' not available`
			);
		}

		return service;
	}

	/**
	 * Check if a service is available
	 */
	hasService(serviceName: keyof InternalToolsServices): boolean {
		return this.services[serviceName] !== undefined;
	}

	/**
	 * Get all available services
	 */
	getAllServices(): InternalToolsServices {
		return { ...this.services };
	}

	/**
	 * Clear all services
	 */
	clear(): void {
		this.services = {};
		this.initialized = false;
		logger.debug('ServiceRegistry: Cleared all services');
	}
}

/**
 * Enhanced internal tools provider with service injection
 */
export class InternalToolsProvider {
	private registry: ServiceRegistry;
	private tools: Map<string, InternalTool> = new Map();
	private initialized = false;

	constructor() {
		this.registry = new ServiceRegistry();
	}

	/**
	 * Initialize the provider
	 */
	async initialize(services?: Partial<InternalToolsServices>): Promise<void> {
		if (this.initialized) {
			logger.warn('InternalToolsProvider: Already initialized');
			return;
		}

		// Register services if provided
		if (services) {
			this.registry.registerServices(services);
		}

		// Register built-in tools
		await this.registerBuiltInTools();

		this.initialized = true;
		logger.info('InternalToolsProvider: Initialized successfully', {
			toolCount: this.tools.size,
			serviceCount: Object.keys(this.registry.getAllServices()).length
		});
	}

	/**
	 * Register a tool with service injection
	 */
	registerTool(tool: InternalTool, requiredServices: (keyof InternalToolsServices)[] = []): void {
		// Validate required services
		for (const serviceName of requiredServices) {
			if (!this.registry.hasService(serviceName)) {
				throw new ToolServiceInjectionError(
					serviceName,
					tool.name,
					`Required service '${serviceName}' not available for tool '${tool.name}'`
				);
			}
		}

		// Create enhanced tool with service injection
		const enhancedTool: InternalTool = {
			...tool,
			handler: async (args: any, context: InternalToolContext) => {
				// Inject services into context
				const enhancedContext: InternalToolContext = {
					...context,
					services: {
						...context.services,
						...this.registry.getAllServices()
					}
				};

				// Execute original handler
				return tool.handler(args, enhancedContext);
			}
		};

		this.tools.set(tool.name, enhancedTool);
		logger.debug(`InternalToolsProvider: Registered tool '${tool.name}'`, {
			requiredServices,
			availableServices: Object.keys(this.registry.getAllServices())
		});
	}

	/**
	 * Unregister a tool
	 */
	unregisterTool(toolName: string): boolean {
		const removed = this.tools.delete(toolName);
		if (removed) {
			logger.debug(`InternalToolsProvider: Unregistered tool '${toolName}'`);
		}
		return removed;
	}

	/**
	 * Get a tool by name
	 */
	getTool(toolName: string): InternalTool | undefined {
		return this.tools.get(toolName);
	}

	/**
	 * Get all tools
	 */
	getAllTools(): InternalToolSet {
		const tools: InternalToolSet = {};
		for (const [name, tool] of this.tools.entries()) {
			tools[name] = tool;
		}
		return tools;
	}

	/**
	 * Check if a tool exists
	 */
	hasTool(toolName: string): boolean {
		return this.tools.has(toolName);
	}

	/**
	 * Get tools by category
	 */
	getToolsByCategory(category: string): InternalToolSet {
		const tools: InternalToolSet = {};
		for (const [name, tool] of this.tools.entries()) {
			if (tool.category === category) {
				tools[name] = tool;
			}
		}
		return tools;
	}

	/**
	 * Register built-in tools
	 */
	private async registerBuiltInTools(): Promise<void> {
		// This would typically load tools from the existing registry
		// For now, we'll create a placeholder that can be extended
		logger.debug('InternalToolsProvider: Registering built-in tools');
		
		// Example tool registration (this would be replaced with actual tool loading)
		// const builtInTools = await this.loadBuiltInTools();
		// for (const tool of builtInTools) {
		//     this.registerTool(tool, tool.requiredServices || []);
		// }
	}

	/**
	 * Get service registry
	 */
	getServiceRegistry(): ServiceRegistry {
		return this.registry;
	}

	/**
	 * Update services
	 */
	updateServices(services: Partial<InternalToolsServices>): void {
		this.registry.registerServices(services);
		logger.debug('InternalToolsProvider: Updated services', {
			serviceNames: Object.keys(services)
		});
	}

	/**
	 * Get statistics
	 */
	getStats(): {
		toolCount: number;
		serviceCount: number;
		availableServices: string[];
		toolsByCategory: Record<string, number>;
	} {
		const toolsByCategory: Record<string, number> = {};
		for (const tool of this.tools.values()) {
			toolsByCategory[tool.category] = (toolsByCategory[tool.category] || 0) + 1;
		}

		return {
			toolCount: this.tools.size,
			serviceCount: Object.keys(this.registry.getAllServices()).length,
			availableServices: Object.keys(this.registry.getAllServices()),
			toolsByCategory
		};
	}

	/**
	 * Check if provider is initialized
	 */
	isInitialized(): boolean {
		return this.initialized;
	}

	/**
	 * Shutdown the provider
	 */
	async shutdown(): Promise<void> {
		this.tools.clear();
		this.registry.clear();
		this.initialized = false;
		logger.info('InternalToolsProvider: Shutdown completed');
	}
}
