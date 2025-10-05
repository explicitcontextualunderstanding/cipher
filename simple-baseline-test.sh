#!/bin/bash

echo "🔍 SIMPLE MCP BASELINE TEST"
echo "=========================="
echo "Timestamp: $(date)"
echo ""

# Test basic SSE connection
echo "1. Testing SSE Connection..."
curl -s -N -H "Accept: text/event-stream" http://localhost:3000/mcp/sse | head -3
echo ""

# Get session ID manually
echo "2. Getting Session ID..."
SESSION_ID=$(curl -s -N -H "Accept: text/event-stream" http://localhost:3000/mcp/sse 2>/dev/null | grep "data: /mcp?sessionId=" | head -1 | sed 's/.*sessionId=\([^]]*\).*/\1/')

if [ -n "$SESSION_ID" ]; then
    echo "✅ Session ID: $SESSION_ID"

    echo ""
    echo "3. Testing Tools List..."
    curl -s -X POST "http://localhost:3000/mcp?sessionId=$SESSION_ID" \
        -H "Content-Type: application/json" \
        -d '{
            "jsonrpc": "2.0",
            "id": "test-'$(date +%s)'",
            "method": "tools/list",
            "params": {}
        }' | jq . 2>/dev/null || echo "Response received (parse failed)"

    echo ""
    echo "4. Testing Memory Search Tool..."
    curl -s -X POST "http://localhost:3000/mcp?sessionId=$SESSION_ID" \
        -H "Content-Type: application/json" \
        -d '{
            "jsonrpc": "2.0",
            "id": "test-search-'$(date +%s)'",
            "method": "tools/call",
            "params": {
                "name": "cipher_memory_search",
                "arguments": {
                    "query": "baseline test query"
                }
            }
        }' | jq . 2>/dev/null || echo "Response received (parse failed)"

    echo ""
    echo "5. Checking Container Logs..."
    echo "Recent tool calls:"
    podman logs cipher_cipher-api_1 --since=2m | grep "Tool called:" | tail -3

    echo ""
    echo "Recent embedding operations:"
    podman logs cipher_cipher-api_1 --since=2m | grep "Embedding" | tail -3

    echo ""
    echo "Recent MCP activity:"
    podman logs cipher_cipher-api_1 --since=2m | grep -E "(MCP|session)" | tail -5

else
    echo "❌ Failed to get session ID"
fi

echo ""
echo "✅ Simple baseline test completed!"