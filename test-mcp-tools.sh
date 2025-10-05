#!/bin/bash

echo "🧪 Testing MCP Tools in Aggregator Mode"
echo "========================================"

# Start SSE connection in background and capture session ID
echo "📡 Establishing SSE connection..."
curl -s -N -H "Accept: text/event-stream" http://localhost:3000/mcp/sse > /tmp/sse_output.log &
CURL_PID=$!

# Wait for session endpoint
sleep 3

# Extract session ID from SSE output
SESSION_ID=$(grep "data: /mcp?sessionId=" /tmp/sse_output.log | head -1 | sed 's/.*sessionId=\([^]]*\).*/\1/')

if [ -z "$SESSION_ID" ]; then
    echo "❌ Failed to get session ID"
    kill $CURL_PID 2>/dev/null
    exit 1
fi

echo "✅ Session ID: $SESSION_ID"

# Test tools list
echo ""
echo "🔧 Testing tools/list..."
RESPONSE=$(curl -s -X POST "http://localhost:3000/mcp?sessionId=$SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {}
  }')

echo "Response: $RESPONSE"

# Test a memory tool if available
echo ""
echo "🧠 Testing cipher_memory_search tool..."
MEMORY_RESPONSE=$(curl -s -X POST "http://localhost:3000/mcp?sessionId=$SESSION_ID" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "cipher_memory_search",
      "arguments": {
        "query": "test search query"
      }
    }
  }')

echo "Memory tool response: $MEMORY_RESPONSE"

# Clean up
kill $CURL_PID 2>/dev/null
rm -f /tmp/sse_output.log

echo ""
echo "✅ MCP testing completed"