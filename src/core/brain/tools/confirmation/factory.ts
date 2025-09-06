import type { IAllowedToolsProvider, ToolConfirmationProvider, ToolConfirmationConfig } from './types.js';
import { MemoryAllowedToolsProvider } from './allowed-tools/memory-provider.js';
import { StorageAllowedToolsProvider } from './allowed-tools/storage-provider.js';
import { DefaultToolConfirmationProvider } from './provider.js';

export class ToolConfirmationFactory {
  static createAllowedToolsProvider(
    storage: 'memory' | 'storage',
    dbPath?: string
  ): IAllowedToolsProvider {
    switch (storage) {
      case 'memory':
        return new MemoryAllowedToolsProvider();
      case 'storage':
        return new StorageAllowedToolsProvider(dbPath);
      default:
        throw new Error(`Unsupported storage type: ${storage}`);
    }
  }

  static createConfirmationProvider(
    config: ToolConfirmationConfig
  ): ToolConfirmationProvider {
    const allowedToolsProvider = this.createAllowedToolsProvider(
      config.allowedToolsStorage,
      config.persistenceDbPath
    );

    return new DefaultToolConfirmationProvider(allowedToolsProvider, config);
  }
}