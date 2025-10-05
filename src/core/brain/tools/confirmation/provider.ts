import { EventEmitter } from 'events';
import type { 
  ToolConfirmationProvider, 
  ToolExecutionDetails, 
  ToolConfirmationResponse,
  ToolConfirmationConfig,
  IAllowedToolsProvider 
} from './types.js';
import { ToolTimeoutError, ToolPermissionError } from '../errors/tool-errors.js';

export class DefaultToolConfirmationProvider extends EventEmitter implements ToolConfirmationProvider {
  public allowedToolsProvider: IAllowedToolsProvider;
  private config: ToolConfirmationConfig;
  private pendingConfirmations = new Map<string, {
    resolve: (value: boolean) => void;
    reject: (error: Error) => void;
    timeout: NodeJS.Timeout;
  }>();

  constructor(allowedToolsProvider: IAllowedToolsProvider, config: ToolConfirmationConfig) {
    super();
    this.allowedToolsProvider = allowedToolsProvider;
    this.config = config;
  }

  async requestConfirmation(details: ToolExecutionDetails): Promise<boolean> {
    // Handle auto modes
    if (this.config.mode === 'auto-approve') {
      await this.allowedToolsProvider.allowTool(details.toolName, details.sessionId);
      return true;
    }
    
    if (this.config.mode === 'auto-deny') {
      return false;
    }

    // Check if already allowed
    const isAllowed = await this.allowedToolsProvider.isToolAllowed(details.toolName, details.sessionId);
    if (isAllowed) {
      return true;
    }

    // Event-based confirmation
    return this.requestEventBasedConfirmation(details);
  }

  private async requestEventBasedConfirmation(details: ToolExecutionDetails): Promise<boolean> {
    const confirmationId = `${details.toolName}-${Date.now()}`;
    
    return new Promise<boolean>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pendingConfirmations.delete(confirmationId);
        reject(new ToolTimeoutError(details.toolName, this.config.timeout));
      }, this.config.timeout);

      this.pendingConfirmations.set(confirmationId, {
        resolve,
        reject,
        timeout
      });

      // Emit event for UI to handle
      this.emit('confirmation-required', {
        confirmationId,
        details
      });
    });
  }

  async handleConfirmationResponse(response: ToolConfirmationResponse): Promise<void> {
    // Find pending confirmation by tool name and approximate timestamp
    const confirmationEntry = Array.from(this.pendingConfirmations.entries())
      .find(([id]) => id.includes(response.sessionId || ''));

    if (!confirmationEntry) {
      return; // No pending confirmation found
    }

    const [confirmationId, { resolve, timeout }] = confirmationEntry;
    
    clearTimeout(timeout);
    this.pendingConfirmations.delete(confirmationId);

    if (response.approved && response.rememberForSession) {
      // Extract tool name from confirmation ID
      const toolName = confirmationId.split('-')[0];
      await this.allowedToolsProvider.allowTool(toolName, response.sessionId);
    }

    resolve(response.approved);
  }

  respondToConfirmation(confirmationId: string, approved: boolean, rememberForSession: boolean = false): void {
    const pending = this.pendingConfirmations.get(confirmationId);
    if (!pending) return;

    const { resolve, timeout } = pending;
    clearTimeout(timeout);
    this.pendingConfirmations.delete(confirmationId);

    if (approved && rememberForSession) {
      const toolName = confirmationId.split('-')[0];
      // Note: We don't have sessionId here, could be improved
      this.allowedToolsProvider.allowTool(toolName);
    }

    resolve(approved);
  }
}