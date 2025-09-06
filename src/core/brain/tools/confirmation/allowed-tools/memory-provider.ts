import type { IAllowedToolsProvider } from '../types.js';

export class MemoryAllowedToolsProvider implements IAllowedToolsProvider {
  private allowedTools = new Map<string, Set<string>>();
  private globalAllowed = new Set<string>();

  async isToolAllowed(toolName: string, sessionId?: string): Promise<boolean> {
    if (sessionId) {
      const sessionTools = this.allowedTools.get(sessionId);
      return sessionTools?.has(toolName) ?? false;
    }
    return this.globalAllowed.has(toolName);
  }

  async allowTool(toolName: string, sessionId?: string): Promise<void> {
    if (sessionId) {
      if (!this.allowedTools.has(sessionId)) {
        this.allowedTools.set(sessionId, new Set());
      }
      this.allowedTools.get(sessionId)!.add(toolName);
    } else {
      this.globalAllowed.add(toolName);
    }
  }

  async disallowTool(toolName: string, sessionId?: string): Promise<void> {
    if (sessionId) {
      const sessionTools = this.allowedTools.get(sessionId);
      sessionTools?.delete(toolName);
    } else {
      this.globalAllowed.delete(toolName);
    }
  }

  async getAllowedTools(sessionId?: string): Promise<string[]> {
    if (sessionId) {
      const sessionTools = this.allowedTools.get(sessionId);
      return sessionTools ? Array.from(sessionTools) : [];
    }
    return Array.from(this.globalAllowed);
  }

  async clearAllowedTools(sessionId?: string): Promise<void> {
    if (sessionId) {
      this.allowedTools.delete(sessionId);
    } else {
      this.globalAllowed.clear();
    }
  }
}