#!/bin/bash
# Simple Cipher Memory Commands for Chat Interface

API_BASE="http://127.0.0.1:3001"

case "$1" in
  "store")
    if [ -z "$3" ]; then
      echo "Usage: $0 store <sessionId> <message>"
      exit 1
    fi
    curl -s -X POST "$API_BASE/sessions" -H "Content-Type: application/json" -d "{\"sessionId\": \"$2\"}" > /dev/null
    curl -s -X POST "$API_BASE/message" -H "Content-Type: application/json" -d "{\"message\": \"$3\", \"sessionId\": \"$2\"}" | jq -r '.data.message'
    ;;
  "search")
    if [ -z "$2" ]; then
      echo "Usage: $0 search <sessionId>"
      exit 1
    fi
    curl -s -X GET "$API_BASE/sessions/$2/history" | jq -r '.data.history[] | select(.role == "user") | .content[].text'
    ;;
  "list")
    curl -s -X GET "$API_BASE/sessions" | jq -r '.data.sessions[].id'
    ;;
  *)
    echo "Simple Cipher Memory Commands:"
    echo "  $0 store <sessionId> <message>    # Store information"
    echo "  $0 search <sessionId>           # Search stored information"
    echo "  $0 list                        # List all sessions"
    ;;
esac