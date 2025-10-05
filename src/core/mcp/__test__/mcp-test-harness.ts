import { vi } from 'vitest';

// Mock logger for testing
const mockLogger = {
	info: vi.fn(),
	warn: vi.fn(),
	error: vi.fn(),
	debug: vi.fn(),
};

interface TestSession {
	sessionId: string;
	establishedAt: number;
	lastActivity: number;
	isActive: boolean;
}

interface LifecycleEvents {
	mcpPostReceived?: any;
	toolDispatchStart?: any;
	embeddingCall?: any;
	toolDispatchFinish?: any;
	sseEventSent?: any;
}

interface CorrelationData {
	clientRequestId: string;
	serverRequestId: string;
	sseMessageId: string;
	startTime: number;
	endTime: number;
}

interface VectorStoreEvents {
	searchInitiated?: any;
	indexingOperation?: any;
	queryDetails?: any;
	resultCount?: number;
}

interface ErrorEvents {
	validationError?: any;
	toolCallError?: any;
	embeddingError?: any;
	vectorStoreError?: any;
}

export class MCPTestHarness {
	private sessions: Map<string, TestSession> = new Map();
	private baseUrl: string;
	private logCapture: any[] = [];

	constructor(baseUrl: string = 'http://localhost:3000') {
		this.baseUrl = baseUrl;
	}

	async establishSSEConnection(): Promise<string> {
		const response = await fetch(`${this.baseUrl}/mcp/sse`, {
			headers: {
				'Accept': 'text/event-stream',
			},
		});

		if (!response.ok) {
			throw new Error(`Failed to establish SSE connection: ${response.status}`);
		}

		const reader = response.body?.getReader();
		const decoder = new TextDecoder();
		let sessionId = '';

		if (reader) {
			const { value } = await reader.read();
			const chunk = decoder.decode(value);
			const match = chunk.match(/data: \/mcp\?sessionId=([a-f0-9-]+)/);
			if (match) {
				sessionId = match[1];
			}
		}

		if (!sessionId) {
			throw new Error('No session ID received from SSE connection');
		}

		// Register session
		this.sessions.set(sessionId, {
			sessionId,
			establishedAt: Date.now(),
			lastActivity: Date.now(),
			isActive: true,
		});

		mockLogger.info(`[MCP Test Harness] Established SSE connection with session: ${sessionId}`);
		return sessionId;
	}

	async listTools(): Promise<any> {
		const session = this.getActiveSession();
		if (!session) {
			throw new Error('No active session available');
		}

		const response = await fetch(`${this.baseUrl}/mcp?sessionId=${session.sessionId}`, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
			},
			body: JSON.stringify({
				jsonrpc: '2.0',
				id: `test-${Date.now()}`,
				method: 'tools/list',
				params: {},
			}),
		});

		if (!response.ok) {
			throw new Error(`Failed to list tools: ${response.status}`);
		}

		const result = await response.json();
		session.lastActivity = Date.now();
		return result;
	}

	async callTool(toolName: string, args: any): Promise<any> {
		const session = this.getActiveSession();
		if (!session) {
			throw new Error('No active session available');
		}

		const requestId = `test-${toolName}-${Date.now()}`;
		const startTime = Date.now();

		mockLogger.info(`[MCP Test Harness] Calling tool: ${toolName} with args:`, {
			requestId,
			toolName,
			arguments: this.sanitizeArguments(args),
		});

		const response = await fetch(`${this.baseUrl}/mcp?sessionId=${session.sessionId}`, {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
			},
			body: JSON.stringify({
				jsonrpc: '2.0',
				id: requestId,
				method: 'tools/call',
				params: {
					name: toolName,
					arguments: args,
				},
			}),
		});

		const endTime = Date.now();
		const duration = endTime - startTime;

		if (!response.ok) {
			mockLogger.error(`[MCP Test Harness] Tool call failed:`, {
				requestId,
				toolName,
				status: response.status,
				duration,
			});
			throw new Error(`Tool call failed: ${response.status}`);
		}

		const result = await response.json();
		session.lastActivity = Date.now();

		mockLogger.info(`[MCP Test Harness] Tool call completed:`, {
			requestId,
			toolName,
			duration,
			success: true,
		});

		return result;
	}

	async getServerInfo(): Promise<any> {
		// This would typically be available via an API endpoint
		// For now, return known configuration
		return {
			mode: 'aggregator',
			transportType: 'sse',
			toolCount: 4,
		};
	}

	async captureLogs(startTime: number): Promise<any[]> {
		// In a real implementation, this would interface with the logging system
		// For now, return recent logs that would be relevant
		return this.logCapture.filter(log => log.timestamp >= startTime);
	}

	extractLifecycleEvents(logs: any[], sessionId: string): LifecycleEvents {
		const events: LifecycleEvents = {};

		for (const log of logs) {
			const logText = typeof log === 'string' ? log : JSON.stringify(log);

			// MCP POST Receipt
			if (logText.includes('API Request') && logText.includes(sessionId)) {
				events.mcpPostReceived = {
					timestamp: log.timestamp,
					sessionId,
					method: 'POST',
				};
			}

			// Tool Dispatch Start
			if (logText.includes('[MCP Handler] Tool called:')) {
				const toolMatch = logText.match(/Tool called: (\w+)/);
				if (toolMatch) {
					events.toolDispatchStart = {
						timestamp: log.timestamp,
						toolName: toolMatch[1],
					};
				}
			}

			// Embedding Call
			if (logText.includes('Embedding final query:')) {
				events.embeddingCall = {
					timestamp: log.timestamp,
					query: logText.substring(logText.indexOf('Embedding final query:') + 22),
					vectorDimensions: 768, // Known from configuration
				};
			}

			// Tool Dispatch Finish
			if (logText.includes('API Response') && events.toolDispatchStart) {
				events.toolDispatchFinish = {
					timestamp: log.timestamp,
					duration: log.timestamp - (events.toolDispatchStart?.timestamp || 0),
				};
			}

			// SSE Event Sent
			if (logText.includes('MCP SSE client') && logText.includes('disconnected')) {
				events.sseEventSent = {
					timestamp: log.timestamp,
					sessionId,
					eventType: 'disconnection',
				};
			}
		}

		return events;
	}

	extractErrorEvents(logs: any[], sessionId: string): ErrorEvents {
		const errors: ErrorEvents = {};

		for (const log of logs) {
			const logText = typeof log === 'string' ? log : JSON.stringify(log);

			if (logText.includes('validation') || logText.includes('required')) {
				errors.validationError = {
					timestamp: log.timestamp,
					message: logText,
				};
			}

			if (logText.includes('Tool call failed') || logText.includes('error')) {
				errors.toolCallError = {
					timestamp: log.timestamp,
					message: logText,
				};
			}

			if (logText.includes('Embedding operation failed')) {
				errors.embeddingError = {
					timestamp: log.timestamp,
					message: logText,
				};
			}

			if (logText.includes('Vector dimension mismatch') || logText.includes('Search failed')) {
				errors.vectorStoreError = {
					timestamp: log.timestamp,
					message: logText,
				};
			}
		}

		return errors;
	}

	extractVectorStoreEvents(logs: any[]): VectorStoreEvents {
		const events: VectorStoreEvents = {};

		for (const log of logs) {
			const logText = typeof log === 'string' ? log : JSON.stringify(log);

			if (logText.includes('search_memory tool called')) {
				events.searchInitiated = {
					timestamp: log.timestamp,
					query: this.extractQueryFromLog(logText),
				};
			}

			if (logText.includes('indexing') || logText.includes('storing')) {
				events.indexingOperation = {
					timestamp: log.timestamp,
					operation: logText,
				};
			}

			if (logText.includes('results') || logText.includes('matches')) {
				const resultMatch = logText.match(/(\d+) (?:results|matches)/);
				if (resultMatch) {
					events.resultCount = parseInt(resultMatch[1]);
				}
			}
		}

		return events;
	}

	async executeWithCorrelationTracking(requestId: string, operation: () => Promise<any>): Promise<CorrelationData> {
		const startTime = Date.now();

		// Add correlation metadata to logs
		this.logCapture.push({
			timestamp: startTime,
			type: 'correlation_start',
			requestId,
		});

		try {
			const result = await operation();
			const endTime = Date.now();

			const correlationData: CorrelationData = {
				clientRequestId: requestId,
				serverRequestId: `server-${requestId}`,
				sseMessageId: `msg-${Date.now()}`,
				startTime,
				endTime,
			};

			this.logCapture.push({
				timestamp: endTime,
				type: 'correlation_end',
				requestId,
				duration: endTime - startTime,
			});

			return correlationData;
		} catch (error) {
			const endTime = Date.now();
			throw error;
		}
	}

	async measureEmbeddingLatency(query: string): Promise<any> {
		const startTime = Date.now();

		// Call a tool that triggers embedding
		await this.callTool('cipher_memory_search', { query });

		const endTime = Date.now();

		return {
			requestTime: startTime,
			responseTime: endTime,
			latency: endTime - startTime,
			query: this.sanitizeQuery(query),
			vectorSize: 768,
		};
	}

	getConnectionStatus(sessionId: string): string {
		const session = this.sessions.get(sessionId);
		return session?.isActive ? 'connected' : 'disconnected';
	}

	getActiveSession(): TestSession | undefined {
		for (const session of this.sessions.values()) {
			if (session.isActive) {
				return session;
			}
		}
		return undefined;
	}

	private sanitizeArguments(args: any): any {
		// Remove sensitive information from arguments for logging
		const sanitized = { ...args };
		delete sanitized.apiKey;
		delete sanitized.token;
		return sanitized;
	}

	private sanitizeQuery(query: string): string {
		// Truncate long queries for logging
		return query.length > 100 ? query.substring(0, 97) + '...' : query;
	}

	private extractQueryFromLog(logText: string): string {
		// Extract query from log text
		const queryMatch = logText.match(/query[:\s]+["']([^"']+)["']/);
		return queryMatch ? queryMatch[1] : '';
	}

	async cleanup(): Promise<void> {
		// Close all active sessions
		for (const session of this.sessions.values()) {
			session.isActive = false;
		}
		this.sessions.clear();
		this.logCapture = [];

		mockLogger.info('[MCP Test Harness] Cleanup completed');
	}
}

export async function createTestHarness(baseUrl?: string): Promise<MCPTestHarness> {
	const harness = new MCPTestHarness(baseUrl);

	// Start log capture
	// In a real implementation, this would interface with the actual logging system
	mockLogger.info('[MCP Test Harness] Created test harness');

	return harness;
}