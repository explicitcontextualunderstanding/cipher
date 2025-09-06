export class ToolError extends Error {
  constructor(
    message: string,
    public code: string,
    public toolName?: string,
    public cause?: Error
  ) {
    super(message);
    this.name = 'ToolError';
  }
}

export class ToolConfirmationError extends ToolError {
  constructor(message: string, toolName?: string, cause?: Error) {
    super(message, 'TOOL_CONFIRMATION_ERROR', toolName, cause);
    this.name = 'ToolConfirmationError';
  }
}

export class ToolTimeoutError extends ToolError {
  constructor(toolName: string, timeout: number) {
    super(`Tool confirmation timeout after ${timeout}ms`, 'TOOL_TIMEOUT_ERROR', toolName);
    this.name = 'ToolTimeoutError';
  }
}

export class ToolPermissionError extends ToolError {
  constructor(toolName: string, sessionId?: string) {
    super(
      `Tool '${toolName}' not allowed${sessionId ? ` for session ${sessionId}` : ''}`,
      'TOOL_PERMISSION_ERROR',
      toolName
    );
    this.name = 'ToolPermissionError';
  }
}

export class ToolPrefixError extends ToolError {
  constructor(toolName: string, expectedPrefix: string) {
    super(
      `Tool '${toolName}' does not have expected prefix '${expectedPrefix}'`,
      'TOOL_PREFIX_ERROR',
      toolName
    );
    this.name = 'ToolPrefixError';
  }
}

// Additional error classes needed by unified-tool-manager.ts
export class ToolSystemError extends ToolError {
  constructor(message: string, cause?: Error, context?: Record<string, any>) {
    super(message, 'TOOL_SYSTEM_ERROR', undefined, cause);
    this.name = 'ToolSystemError';
    if (context) {
      Object.assign(this, { context });
    }
  }
}

export class ToolNotAllowedError extends ToolError {
  constructor(
    toolName: string, 
    sessionId?: string, 
    context?: { reason?: string; confirmationResult?: any }
  ) {
    const message = `Tool '${toolName}' not allowed${sessionId ? ` for session ${sessionId}` : ''}${
      context?.reason ? `: ${context.reason}` : ''
    }`;
    super(message, 'TOOL_NOT_ALLOWED_ERROR', toolName);
    this.name = 'ToolNotAllowedError';
    if (context) {
      Object.assign(this, { context });
    }
  }
}

export class ToolNotFoundError extends ToolError {
  constructor(toolName: string, source?: string) {
    const message = `Tool '${toolName}' not found${source ? ` in ${source} tools` : ''}`;
    super(message, 'TOOL_NOT_FOUND_ERROR', toolName);
    this.name = 'ToolNotFoundError';
  }
}

export class ToolExecutionError extends ToolError {
  constructor(
    toolName: string, 
    message: string, 
    cause?: Error, 
    context?: { sessionId?: string; executionId?: string; duration?: number }
  ) {
    super(`Tool execution failed for '${toolName}': ${message}`, 'TOOL_EXECUTION_ERROR', toolName, cause);
    this.name = 'ToolExecutionError';
    if (context) {
      Object.assign(this, { context });
    }
  }
}

// Additional utility error for validation
export class ToolValidationError extends ToolError {
  constructor(toolName: string, message: string, validationErrors?: any) {
    super(`Tool validation failed for '${toolName}': ${message}`, 'TOOL_VALIDATION_ERROR', toolName);
    this.name = 'ToolValidationError';
    if (validationErrors) {
      Object.assign(this, { validationErrors });
    }
  }
}

// Error for configuration issues
export class ToolConfigurationError extends ToolError {
  constructor(message: string, configKey?: string, cause?: Error) {
    super(`Tool configuration error: ${message}`, 'TOOL_CONFIGURATION_ERROR', undefined, cause);
    this.name = 'ToolConfigurationError';
    if (configKey) {
      Object.assign(this, { configKey });
    }
  }
}