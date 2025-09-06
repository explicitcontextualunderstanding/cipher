import Database from 'better-sqlite3';
import type { IAllowedToolsProvider } from '../types.js';

export class StorageAllowedToolsProvider implements IAllowedToolsProvider {
  private db: Database.Database;

  constructor(dbPath: string = 'data/cipher-tool-permissions.db') {
    this.db = new Database(dbPath);
    this.initializeDatabase();
  }

  private initializeDatabase(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS allowed_tools (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tool_name TEXT NOT NULL,
        session_id TEXT,
        created_at INTEGER NOT NULL DEFAULT (unixepoch()),
        UNIQUE(tool_name, session_id)
      )
    `);
  }

  async isToolAllowed(toolName: string, sessionId?: string): Promise<boolean> {
    const stmt = this.db.prepare(`
      SELECT 1 FROM allowed_tools 
      WHERE tool_name = ? AND session_id = ?
    `);
    
    const result = stmt.get(toolName, sessionId || null);
    return result !== undefined;
  }

  async allowTool(toolName: string, sessionId?: string): Promise<void> {
    const stmt = this.db.prepare(`
      INSERT OR IGNORE INTO allowed_tools (tool_name, session_id)
      VALUES (?, ?)
    `);
    
    stmt.run(toolName, sessionId || null);
  }

  async disallowTool(toolName: string, sessionId?: string): Promise<void> {
    const stmt = this.db.prepare(`
      DELETE FROM allowed_tools 
      WHERE tool_name = ? AND session_id = ?
    `);
    
    stmt.run(toolName, sessionId || null);
  }

  async getAllowedTools(sessionId?: string): Promise<string[]> {
    const stmt = this.db.prepare(`
      SELECT tool_name FROM allowed_tools 
      WHERE session_id = ?
      ORDER BY tool_name
    `);
    
    const results = stmt.all(sessionId || null) as { tool_name: string }[];
    return results.map(row => row.tool_name);
  }

  async clearAllowedTools(sessionId?: string): Promise<void> {
    const stmt = this.db.prepare(`
      DELETE FROM allowed_tools 
      WHERE session_id = ?
    `);
    
    stmt.run(sessionId || null);
  }

  close(): void {
    this.db.close();
  }
}