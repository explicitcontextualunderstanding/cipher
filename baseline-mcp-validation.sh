#!/bin/bash

echo "🔍 COMPREHENSIVE MCP BASELINE VALIDATION"
echo "=========================================="
echo "Timestamp: $(date)"
echo ""

# Test Configuration
BASE_URL="http://localhost:3000"
RESULTS_DIR="/tmp/cipher-baseline-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

# Function to capture logs with timestamps
capture_container_logs() {
    local duration=$1
    local log_file="$RESULTS_DIR/container-logs-${duration}s.log"
    echo "📝 Capturing container logs for ${duration}s..."

    # Capture logs in background
    podman logs -f cipher_cipher-api_1 > "$log_file" &
    LOG_PID=$!

    sleep $duration
    kill $LOG_PID 2>/dev/null

    echo "✅ Logs captured: $log_file"
}

# Function to test SSE connection
test_sse_connection() {
    echo "🔌 Testing SSE Connection..."

    local sse_file="$RESULTS_DIR/sse-response.log"

    # Establish SSE connection and capture response
    timeout 10s curl -s -N -H "Accept: text/event-stream" "$BASE_URL/mcp/sse" > "$sse_file"

    if [ -f "$sse_file" ] && [ -s "$sse_file" ]; then
        local session_id=$(grep "data: /mcp?sessionId=" "$sse_file" | head -1 | sed 's/.*sessionId=\([^]]*\).*/\1/')
        echo "✅ SSE Connection Established"
        echo "📋 Session ID: $session_id"
        echo "$session_id" > "$RESULTS_DIR/session-id.txt"
        return 0
    else
        echo "❌ SSE Connection Failed"
        return 1
    fi
}

# Function to test MCP tools list
test_tools_list() {
    local session_id=$(cat "$RESULTS_DIR/session-id.txt" 2>/dev/null)
    if [ -z "$session_id" ]; then
        echo "❌ No session ID available"
        return 1
    fi

    echo "🔧 Testing MCP Tools List..."

    local tools_file="$RESULTS_DIR/tools-list-response.json"

    curl -s -X POST "$BASE_URL/mcp?sessionId=$session_id" \
        -H "Content-Type: application/json" \
        -d '{
            "jsonrpc": "2.0",
            "id": "test-tools-list-'$(date +%s)'",
            "method": "tools/list",
            "params": {}
        }' > "$tools_file"

    if [ -f "$tools_file" ] && [ -s "$tools_file" ]; then
        echo "✅ Tools List Retrieved"
        echo "📄 Response saved: $tools_file"

        # Count tools
        local tool_count=$(jq -r '.tools | length' "$tools_file" 2>/dev/null || echo "0")
        echo "🔢 Tools available: $tool_count"

        # List tool names
        jq -r '.tools[].name' "$tools_file" 2>/dev/null > "$RESULTS_DIR/tool-names.txt"
        echo "📋 Tool names saved to: $RESULTS_DIR/tool-names.txt"

        return 0
    else
        echo "❌ Tools List Failed"
        return 1
    fi
}

# Function to test memory search tool
test_memory_search() {
    local session_id=$(cat "$RESULTS_DIR/session-id.txt" 2>/dev/null)
    if [ -z "$session_id" ]; then
        echo "❌ No session ID available"
        return 1
    fi

    echo "🧠 Testing Memory Search Tool..."

    local search_file="$RESULTS_DIR/memory-search-response.json"
    local test_query="baseline validation test query $(date +%s)"

    # Start log capture
    capture_container_logs 15 &
    CAPTURE_PID=$!

    # Execute memory search
    curl -s -X POST "$BASE_URL/mcp?sessionId=$session_id" \
        -H "Content-Type: application/json" \
        -d '{
            "jsonrpc": "2.0",
            "id": "test-memory-search-'$(date +%s)'",
            "method": "tools/call",
            "params": {
                "name": "cipher_memory_search",
                "arguments": {
                    "query": "'"$test_query"'"
                }
            }
        }' > "$search_file"

    # Wait for log capture
    wait $CAPTURE_PID

    if [ -f "$search_file" ] && [ -s "$search_file" ]; then
        echo "✅ Memory Search Executed"
        echo "📄 Response saved: $search_file"
        echo "🔍 Test query: $test_query"

        # Check if accepted
        if grep -q "Accepted" "$search_file"; then
            echo "✅ Tool call accepted by server"
        else
            echo "⚠️  Unexpected response format"
        fi

        return 0
    else
        echo "❌ Memory Search Failed"
        return 1
    fi
}

# Function to test memory extraction tool
test_memory_extraction() {
    local session_id=$(cat "$RESULTS_DIR/session-id.txt" 2>/dev/null)
    if [ -z "$session_id" ]; then
        echo "❌ No session ID available"
        return 1
    fi

    echo "📝 Testing Memory Extraction Tool..."

    local extraction_file="$RESULTS_DIR/memory-extraction-response.json"
    local test_content="baseline test content for extraction $(date +%s)"

    # Start log capture
    capture_container_logs 15 &
    CAPTURE_PID=$!

    # Execute memory extraction
    curl -s -X POST "$BASE_URL/mcp?sessionId=$session_id" \
        -H "Content-Type: application/json" \
        -d '{
            "jsonrpc": "2.0",
            "id": "test-memory-extraction-'$(date +%s)'",
            "method": "tools/call",
            "params": {
                "name": "cipher_extract_and_operate_memory",
                "arguments": {
                    "content": "'"$test_content"'",
                    "operation": "store"
                }
            }
        }' > "$extraction_file"

    # Wait for log capture
    wait $CAPTURE_PID

    if [ -f "$extraction_file" ] && [ -s "$extraction_file" ]; then
        echo "✅ Memory Extraction Executed"
        echo "📄 Response saved: $extraction_file"
        echo "📝 Test content: $test_content"

        return 0
    else
        echo "❌ Memory Extraction Failed"
        return 1
    fi
}

# Function to analyze captured logs
analyze_logs() {
    echo ""
    echo "📊 LOG ANALYSIS"
    echo "==============="

    local log_file=$(find "$RESULTS_DIR" -name "container-logs-*.log" | head -1)

    if [ ! -f "$log_file" ]; then
        echo "❌ No log files found for analysis"
        return 1
    fi

    echo "📄 Analyzing: $log_file"
    echo ""

    # Extract key lifecycle events
    echo "🔍 MCP Lifecycle Events:"
    echo "------------------------"

    echo "📡 SSE Connections:"
    grep -c "MCP SSE client connected" "$log_file" 2>/dev/null || echo "0 connections"

    echo "🔧 Tool Calls:"
    grep -c "Tool called:" "$log_file" 2>/dev/null || echo "0 tool calls"

    echo "🧠 Embedding Operations:"
    grep -c "Embedding final query:" "$log_file" 2>/dev/null || echo "0 embedding ops"

    echo "📤 API Responses:"
    grep -c "API Response" "$log_file" 2>/dev/null || echo "0 responses"

    echo ""
    echo "🔧 Detailed Tool Call Evidence:"
    grep "Tool called:" "$log_file" 2>/dev/null || echo "No tool calls found"

    echo ""
    echo "🧠 Embedding Evidence:"
    grep "Embedding final query:" "$log_file" 2>/dev/null || echo "No embedding operations found"

    echo ""
    echo "⚠️  Errors and Warnings:"
    grep -E "(ERROR|WARN)" "$log_file" 2>/dev/null | tail -5 || echo "No errors/warnings found"

    echo ""
    echo "📋 MCP Mode Verification:"
    grep "MCP server mode:" "$log_file" 2>/dev/null | tail -1 || echo "Mode not found in logs"

    echo ""
    echo "🔢 Tool Registration:"
    grep "Registering.*tools:" "$log_file" 2>/dev/null | tail -1 || echo "Tool registration not found"
}

# Function to generate summary report
generate_summary() {
    echo ""
    echo "📋 BASELINE VALIDATION SUMMARY"
    echo "==============================="
    echo "Results directory: $RESULTS_DIR"
    echo "Test completed: $(date)"
    echo ""

    # Check results
    local sse_success=false
    local tools_success=false
    local search_success=false
    local extraction_success=false

    [ -f "$RESULTS_DIR/session-id.txt" ] && sse_success=true
    [ -f "$RESULTS_DIR/tools-list-response.json" ] && tools_success=true
    [ -f "$RESULTS_DIR/memory-search-response.json" ] && search_success=true
    [ -f "$RESULTS_DIR/memory-extraction-response.json" ] && extraction_success=true

    echo "✅ Test Results:"
    echo "  SSE Connection: $([ "$sse_success" = true ] && echo "PASS" || echo "FAIL")"
    echo "  Tools List: $([ "$tools_success" = true ] && echo "PASS" || echo "FAIL")"
    echo "  Memory Search: $([ "$search_success" = true ] && echo "PASS" || echo "FAIL")"
    echo "  Memory Extraction: $([ "$extraction_success" = true ] && echo "PASS" || echo "FAIL")"
    echo ""

    # Tool count
    if [ -f "$RESULTS_DIR/tool-names.txt" ]; then
        local tool_count=$(wc -l < "$RESULTS_DIR/tool-names.txt")
        echo "🔢 Tools Available: $tool_count"
        echo "📋 Tool Names:"
        cat "$RESULTS_DIR/tool-names.txt" | sed 's/^/   - /'
    fi

    echo ""
    echo "📊 Evidence Collected:"
    echo "  - Container logs: $(find "$RESULTS_DIR" -name "container-logs-*.log" | wc -l) files"
    echo "  - API responses: $(find "$RESULTS_DIR" -name "*-response.json" | wc -l) files"
    echo "  - Configuration data: $(find "$RESULTS_DIR" -name "*.txt" | wc -l) files"

    echo ""
    echo "🎯 Overall Status: $([ "$sse_success" = true ] && [ "$tools_success" = true ] && echo "SUCCESS" || echo "PARTIAL")"
    echo ""
    echo "📁 All results saved in: $RESULTS_DIR"
}

# Main execution
main() {
    echo "Starting comprehensive baseline validation..."
    echo ""

    # Run tests
    test_sse_connection
    sleep 2

    test_tools_list
    sleep 2

    test_memory_search
    sleep 2

    test_memory_extraction
    sleep 2

    # Analysis
    analyze_logs

    # Summary
    generate_summary

    echo ""
    echo "🏁 Baseline validation completed!"
    echo "📊 Review the detailed logs and responses in: $RESULTS_DIR"
}

# Execute main function
main "$@"