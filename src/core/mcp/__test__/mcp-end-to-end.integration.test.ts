import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createTestHarness } from './mcp-test-harness.js';

describe('MCP End-to-End Integration Tests', () => {
	let testHarness: any;
	let sessionId: string;

	beforeEach(async () => {
		testHarness = await createTestHarness();
		sessionId = await testHarness.establishSSEConnection();
	});

	afterEach(async () => {
		await testHarness?.cleanup();
	});

	describe('MCP Server Configuration', () => {
		it('should initialize MCP server in aggregator mode', async () => {
			const serverInfo = await testHarness.getServerInfo();
			expect(serverInfo.mode).toBe('aggregator');
			expect(serverInfo.transportType).toBe('sse');
		});

		it('should register all expected tools in aggregator mode', async () => {
			const toolsResponse = await testHarness.listTools();
			const toolNames = toolsResponse.tools.map((t: any) => t.name);

			// Verify all 4 aggregator tools are available
			expect(toolNames).toContain('cipher_extract_and_operate_memory');
			expect(toolNames).toContain('cipher_memory_search');
			expect(toolNames).toContain('cipher_bash');
			expect(toolNames).toContain('cipher_web_search');

			// Verify tool count
			expect(toolNames.length).toBe(4);
		});
	});

	describe('MCP Tool Call Lifecycle', () => {
		it('should execute cipher_memory_search with full lifecycle logging', async () => {
			const startTime = Date.now();
			const testQuery = "test integration query";

			// Initiate tool call
			const toolCallPromise = testHarness.callTool('cipher_memory_search', {
				query: testQuery
			});

			// Capture intermediate logs
			const logs = await testHarness.captureLogs(startTime);

			// Verify tool call completes
			const result = await toolCallPromise;
			expect(result).toBeDefined();

			// Verify full lifecycle evidence in logs
			const lifecycleEvents = testHarness.extractLifecycleEvents(logs, sessionId);

			// 1. MCP POST Receipt
			expect(lifecycleEvents.mcpPostReceived).toBeDefined();
			expect(lifecycleEvents.mcpPostReceived.toolName).toBe('cipher_memory_search');
			expect(lifecycleEvents.mcpPostReceived.query).toContain(testQuery);

			// 2. Tool Dispatch Start
			expect(lifecycleEvents.toolDispatchStart).toBeDefined();
			expect(lifecycleEvents.toolDispatchStart.toolName).toBe('cipher_memory_search');

			// 3. Embedding Call
			expect(lifecycleEvents.embeddingCall).toBeDefined();
			expect(lifecycleEvents.embeddingCall.query).toContain(testQuery);
			expect(lifecycleEvents.embeddingCall.vectorDimensions).toBe(768);

			// 4. Tool Dispatch Finish
			expect(lifecycleEvents.toolDispatchFinish).toBeDefined();

			// 5. SSE Event Sent
			expect(lifecycleEvents.sseEventSent).toBeDefined();
		});

		it('should execute cipher_extract_and_operate_memory with detailed logging', async () => {
			const startTime = Date.now();
			const testContent = "test memory content for extraction";

			const result = await testHarness.callTool('cipher_extract_and_operate_memory', {
				content: testContent,
				operation: "store"
			});

			const logs = await testHarness.captureLogs(startTime);
			const lifecycleEvents = testHarness.extractLifecycleEvents(logs, sessionId);

			// Verify extraction-specific operations
			expect(lifecycleEvents.toolDispatchStart.toolName).toBe('cipher_extract_and_operate_memory');
			expect(lifecycleEvents.embeddingCall?.query).toContain(testContent);
		});

		it('should handle errors gracefully and log detailed error information', async () => {
			const startTime = Date.now();

			// Intentionally call with invalid parameters
			try {
				await testHarness.callTool('cipher_memory_search', {
					// Missing required 'query' parameter
				});
			} catch (error) {
				// Expected to fail
			}

			const logs = await testHarness.captureLogs(startTime);
			const errorEvents = testHarness.extractErrorEvents(logs, sessionId);

			// Verify error logging
			expect(errorEvents.validationError || errorEvents.toolCallError).toBeDefined();
			if (errorEvents.validationError) {
				expect(errorEvents.validationError.parameter).toBe('query');
			}
		});
	});

	describe('Bidirectional Protocol Events', () => {
		it('should maintain stable SSE connection during tool execution', async () => {
			const initialConnectionStatus = testHarness.getConnectionStatus(sessionId);
			expect(initialConnectionStatus).toBe('connected');

			// Execute tool that takes some time
			await testHarness.callTool('cipher_memory_search', {
				query: "test query for connection stability"
			});

			const finalConnectionStatus = testHarness.getConnectionStatus(sessionId);
			expect(finalConnectionStatus).toBe('connected');
		});

		it('should correlate client requests with server processing using unique IDs', async () => {
			const requestId = `test-request-${Date.now()}`;
			const testQuery = "correlation test query";

			const correlationData = await testHarness.executeWithCorrelationTracking(requestId, () =>
				testHarness.callTool('cipher_memory_search', { query: testQuery })
			);

			// Verify request ID is preserved through the lifecycle
			expect(correlationData.clientRequestId).toBe(requestId);
			expect(correlationData.serverRequestId).toContain(requestId);
			expect(correlationData.sseMessageId).toBeDefined();
		});
	});

	describe('Performance and Latency', () => {
		it('should complete tool calls within acceptable time limits', async () => {
			const startTime = Date.now();

			await testHarness.callTool('cipher_memory_search', {
				query: "performance test query"
			});

			const endTime = Date.now();
			const duration = endTime - startTime;

			// Should complete within 30 seconds (adjust based on expected performance)
			expect(duration).toBeLessThan(30000);
		});

		it('should measure embedding API latency', async () => {
			const embeddingMetrics = await testHarness.measureEmbeddingLatency("test query for latency");

			expect(embeddingMetrics.requestTime).toBeGreaterThan(0);
			expect(embeddingMetrics.responseTime).toBeGreaterThan(embeddingMetrics.requestTime);
			expect(embeddingMetrics.latency).toBeGreaterThan(0);
			expect(embeddingMetrics.vectorSize).toBe(768);
		});
	});

	describe('Vector Store Integration', () => {
		it('should log vector store interactions during memory operations', async () => {
			const startTime = Date.now();
			const testQuery = "vector store integration test";

			await testHarness.callTool('cipher_memory_search', {
				query: testQuery
			});

			const logs = await testHarness.captureLogs(startTime);
			const vectorStoreEvents = testHarness.extractVectorStoreEvents(logs);

			// Verify vector store operations
			expect(vectorStoreEvents.searchInitiated || vectorStoreEvents.indexingOperation).toBeDefined();
			if (vectorStoreEvents.searchInitiated) {
				expect(vectorStoreEvents.searchInitiated.query).toContain(testQuery);
			}
		});
	});

	describe('Security and Secrets Handling', () => {
		it('should not expose API keys in logs', async () => {
			const startTime = Date.now();

			await testHarness.callTool('cipher_memory_search', {
				query: "security test query"
			});

			const logs = await testHarness.captureLogs(startTime);
			const logText = logs.map((log: any) => JSON.stringify(log)).join(' ');

			// Verify no API keys are exposed in logs
			expect(logText).not.toContain('sk-');
			expect(logText).not.toContain('api_key');
			expect(logText).not.toMatch(/\b[a-f0-9]{39,}\b/); // API key patterns
		});
	});
});