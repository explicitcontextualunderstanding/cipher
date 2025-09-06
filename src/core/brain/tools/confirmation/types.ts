import { z } from 'zod';

export interface ToolExecutionDetails {
  toolName: string;
  description?: string;
  arguments: Record<string, any>;
  source: 'mcp' | 'internal';
  sessionId?: string;
  timestamp: number;
}

export interface ToolConfirmationResponse {
  approved: boolean;
  rememberForSession: boolean;
  timestamp: number;
  sessionId?: string;
}

export const ToolConfirmationModeSchema = z.enum(['event-based', 'auto-approve', 'auto-deny']);
export type ToolConfirmationMode = z.infer<typeof ToolConfirmationModeSchema>;

export const ToolConfirmationConfigSchema = z.object({
  mode: z.enum(['event-based', 'auto-approve', 'auto-deny']).default('event-based'),
  timeout: z.number().min(1000).max(300000).default(30000), // 1s to 5min
  allowedToolsStorage: z.enum(['memory', 'storage']).default('storage'),
  requireConfirmationForMcp: z.boolean().default(true),
  requireConfirmationForInternal: z.boolean().default(true),
  persistenceDbPath: z.string().optional()
});
export const InternalToolsConfigSchema = z.object({
  enabledServices: z.object({
    searchService: z.boolean().default(true),
    sessionManager: z.boolean().default(true),
    fileService: z.boolean().default(true),
    embeddingManager: z.boolean().default(true)
  }),
  serviceConfig: z.record(z.any()).optional()
});
export const UnifiedToolsConfigSchema = z.object({
  confirmation: ToolConfirmationConfigSchema,
  internalTools: InternalToolsConfigSchema,
  prefixing: z.object({
    mcpPrefix: z.string().default('mcp--'),
    internalPrefix: z.string().default('internal--'),
    legacyPrefix: z.string().default('cipher_') // For backward compatibility
  })
});
export type ToolConfirmationConfig = z.infer<typeof ToolConfirmationConfigSchema>;
export type InternalToolsConfig = z.infer<typeof InternalToolsConfigSchema>;
export type UnifiedToolsConfig = z.infer<typeof UnifiedToolsConfigSchema>;

export interface IAllowedToolsProvider {
  isToolAllowed(toolName: string, sessionId?: string): Promise<boolean>;
  allowTool(toolName: string, sessionId?: string): Promise<void>;
  disallowTool(toolName: string, sessionId?: string): Promise<void>;
  getAllowedTools(sessionId?: string): Promise<string[]>;
  clearAllowedTools(sessionId?: string): Promise<void>;
}

export interface ToolConfirmationProvider {
  allowedToolsProvider: IAllowedToolsProvider;
  requestConfirmation(details: ToolExecutionDetails): Promise<boolean>;
  handleConfirmationResponse?(response: ToolConfirmationResponse): Promise<void>;
}