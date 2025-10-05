# Local Embedding Service for Cipher

This Go service provides OpenAI-compatible embeddings using Google's Generative Language API, enabling Cipher's memory tools when external embedding services aren't available.

## Setup

### 1. Install Dependencies
```bash
cd embedding-service
go mod tidy
```

### 2. Set Google API Key
```bash
export GOOGLE_API_KEY="your-google-api-key"
```

### 3. Build and Run
```bash
go build -o embedding-service main.go
./embedding-service
```

The service will start on port 5000 by default.

## Endpoints

### POST /v1/embeddings
OpenAI-compatible embeddings endpoint.

**Request:**
```json
{
  "input": "Hello, world!",
  "model": "text-embedding-004"
}
```

**Response:**
```json
{
  "object": "list",
  "data": [
    {
      "object": "embedding",
      "embedding": [0.1, 0.2, 0.3, ...],
      "index": 0
    }
  ],
  "model": "text-embedding-004",
  "usage": {
    "prompt_tokens": 2,
    "total_tokens": 2
  }
}
```

### GET /health
Health check endpoint.

## Configure Cipher

Update `memAgent/cipher.yml`:

```yaml
embedding:
  type: openai
  model: text-embedding-004
  apiKey: ""  # No key needed for local service
  baseURL: http://localhost:5000
```

## Environment Variables

- `GOOGLE_API_KEY`: Your Google Generative Language API key
- `PORT`: Service port (default: 5000)

## How it Works

1. Receives OpenAI-compatible embedding requests
2. Uses Google's `text-embedding-004` model via the Generative Language API
3. Returns OpenAI-compatible response format
4. Cipher can now use memory tools that require embeddings