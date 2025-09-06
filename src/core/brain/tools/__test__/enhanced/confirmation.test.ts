/**
 * Tool Confirmation System Tests
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { MemoryAllowedToolsProvider } from '../../confirmation/allowed-tools/memory-provider.js';
import { DefaultToolConfirmationProvider } from '../../confirmation/provider.js';
import { ToolExecutionDetails, ToolConfirmationResponse } from '../../confirmation/types.js';

describe('MemoryAllowedToolsProvider', () => {
	let provider: MemoryAllowedToolsProvider;

	beforeEach(() => {
		provider = new MemoryAllowedToolsProvider();
	});

	describe('isToolAllowed', () => {
		it('should return false for unknown tools', async () => {
			const result = await provider.isToolAllowed('unknown-tool');
			expect(result).toBe(false);
		});

		it('should return true for globally allowed tools', async () => {
			await provider.allowToolGlobally('test-tool');
			const result = await provider.isToolAllowed('test-tool');
			expect(result).toBe(true);
		});

		it('should return true for session-allowed tools', async () => {
			await provider.allowTool('test-tool', 'session-1');
			const result = await provider.isToolAllowed('test-tool', 'session-1');
			expect(result).toBe(true);
		});

		it('should return false for tools not allowed in specific session', async () => {
			await provider.allowTool('test-tool', 'session-1');
			const result = await provider.isToolAllowed('test-tool', 'session-2');
			expect(result).toBe(false);
		});
	});

	describe('allowTool', () => {
		it('should allow tool globally', async () => {
			await provider.allowTool('test-tool');
			const result = await provider.isToolAllowed('test-tool');
			expect(result).toBe(true);
		});

		it('should allow tool for specific session', async () => {
			await provider.allowTool('test-tool', 'session-1');
			const result = await provider.isToolAllowed('test-tool', 'session-1');
			expect(result).toBe(true);
		});
	});

	describe('disallowTool', () => {
		it('should disallow globally allowed tool', async () => {
			await provider.allowToolGlobally('test-tool');
			await provider.disallowTool('test-tool');
			const result = await provider.isToolAllowed('test-tool');
			expect(result).toBe(false);
		});

		it('should disallow session-specific tool', async () => {
			await provider.allowTool('test-tool', 'session-1');
			await provider.disallowTool('test-tool', 'session-1');
			const result = await provider.isToolAllowed('test-tool', 'session-1');
			expect(result).toBe(false);
		});
	});

	describe('getAllowedTools', () => {
		it('should return empty array for no allowed tools', async () => {
			const result = await provider.getAllowedTools();
			expect(result).toEqual([]);
		});

		it('should return global and session tools', async () => {
			await provider.allowToolGlobally('global-tool');
			await provider.allowTool('session-tool', 'session-1');
			
			const globalResult = await provider.getAllowedTools();
			expect(globalResult).toContain('global-tool');
			
			const sessionResult = await provider.getAllowedTools('session-1');
			expect(sessionResult).toContain('global-tool');
			expect(sessionResult).toContain('session-tool');
		});
	});

	describe('clearAllowedTools', () => {
		it('should clear all tools when no session specified', async () => {
			await provider.allowToolGlobally('global-tool');
			await provider.allowTool('session-tool', 'session-1');
			
			await provider.clearAllowedTools();
			
			const globalResult = await provider.getAllowedTools();
			const sessionResult = await provider.getAllowedTools('session-1');
			
			expect(globalResult).toEqual([]);
			expect(sessionResult).toEqual([]);
		});

		it('should clear only session-specific tools', async () => {
			await provider.allowToolGlobally('global-tool');
			await provider.allowTool('session-tool', 'session-1');
			
			await provider.clearAllowedTools('session-1');
			
			const globalResult = await provider.getAllowedTools();
			const sessionResult = await provider.getAllowedTools('session-1');
			
			expect(globalResult).toContain('global-tool');
			expect(sessionResult).toEqual(['global-tool']);
		});
	});
});

describe('DefaultToolConfirmationProvider', () => {
	let provider: DefaultToolConfirmationProvider;
	let allowedToolsProvider: MemoryAllowedToolsProvider;

	beforeEach(() => {
		allowedToolsProvider = new MemoryAllowedToolsProvider();
		provider = new DefaultToolConfirmationProvider(
			allowedToolsProvider,
			{
				mode: 'event-based',
				timeout: 5000,
				allowedToolsStorage: 'memory',
				enableSessionScoping: true,
				defaultAction: 'ask',
			}
		);
	});

	describe('requestConfirmation', () => {
		it('should auto-approve pre-allowed tools', async () => {
			await allowedToolsProvider.allowTool('test-tool', 'session-1');
			
			const details: ToolExecutionDetails = {
				toolName: 'test-tool',
				args: {},
				sessionId: 'session-1',
				source: 'internal',
				timestamp: Date.now(),
				executionId: 'exec-1',
			};

			const result = await provider.requestConfirmation(details);
			expect(result).toBe(true);
		});

		it('should auto-approve in auto-approve mode', async () => {
			provider.updateConfig({ mode: 'auto-approve' });
			
			const details: ToolExecutionDetails = {
				toolName: 'test-tool',
				args: {},
				sessionId: 'session-1',
				source: 'internal',
				timestamp: Date.now(),
				executionId: 'exec-1',
			};

			const result = await provider.requestConfirmation(details);
			expect(result).toBe(true);
		});

		it('should auto-deny in auto-deny mode', async () => {
			provider.updateConfig({ mode: 'auto-deny' });
			
			const details: ToolExecutionDetails = {
				toolName: 'test-tool',
				args: {},
				sessionId: 'session-1',
				source: 'internal',
				timestamp: Date.now(),
				executionId: 'exec-1',
			};

			await expect(provider.requestConfirmation(details)).rejects.toThrow();
		});

		it('should timeout in event-based mode', async () => {
			const details: ToolExecutionDetails = {
				toolName: 'test-tool',
				args: {},
				sessionId: 'session-1',
				source: 'internal',
				timestamp: Date.now(),
				executionId: 'exec-1',
			};

			// Mock setTimeout to make test faster
			vi.useFakeTimers();
			
			const promise = provider.requestConfirmation(details);
			vi.advanceTimersByTime(6000); // Advance past timeout
			
			await expect(promise).rejects.toThrow();
			
			vi.useRealTimers();
		});
	});

	describe('handleConfirmationResponse', () => {
		it('should handle approval response', async () => {
			const details: ToolExecutionDetails = {
				toolName: 'test-tool',
				args: {},
				sessionId: 'session-1',
				source: 'internal',
				timestamp: Date.now(),
				executionId: 'exec-1',
			};

			// Start confirmation request
			const confirmationPromise = provider.requestConfirmation(details);

			// Handle response
			const response: ToolConfirmationResponse = {
				approved: true,
				rememberForSession: true,
				timestamp: Date.now(),
				sessionId: 'session-1',
			};

			await provider.handleConfirmationResponse(response);
			
			const result = await confirmationPromise;
			expect(result).toBe(true);

			// Check if tool was remembered
			const isAllowed = await allowedToolsProvider.isToolAllowed('test-tool', 'session-1');
			expect(isAllowed).toBe(true);
		});

		it('should handle denial response', async () => {
			const details: ToolExecutionDetails = {
				toolName: 'test-tool',
				args: {},
				sessionId: 'session-1',
				source: 'internal',
				timestamp: Date.now(),
				executionId: 'exec-1',
			};

			// Start confirmation request
			const confirmationPromise = provider.requestConfirmation(details);

			// Handle response
			const response: ToolConfirmationResponse = {
				approved: false,
				reason: 'User denied',
				timestamp: Date.now(),
				sessionId: 'session-1',
			};

			await provider.handleConfirmationResponse(response);
			
			await expect(confirmationPromise).rejects.toThrow();
		});
	});
});
