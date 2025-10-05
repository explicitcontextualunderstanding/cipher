package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"

	generativelanguage "cloud.google.com/go/ai/generativelanguage/apiv1"
	generativelanguagepb "cloud.google.com/go/ai/generativelanguage/apiv1/generativelanguagepb"
	"github.com/gorilla/mux"
	"google.golang.org/api/option"
)

// EmbeddingRequest represents OpenAI-compatible embedding request
type EmbeddingRequest struct {
	Input  string `json:"input"`
	Model  string `json:"model"`
	UserID string `json:"user,omitempty"`
}

// EmbeddingResponse represents OpenAI-compatible embedding response
type EmbeddingResponse struct {
	Object string                `json:"object"`
	Data   []EmbeddingData       `json:"data"`
	Model  string                `json:"model"`
	Usage  EmbeddingUsage        `json:"usage"`
}

type EmbeddingData struct {
	Object    string    `json:"object"`
	Embedding []float32 `json:"embedding"`
	Index     int       `json:"index"`
}

type EmbeddingUsage struct {
	PromptTokens int `json:"prompt_tokens"`
	TotalTokens  int `json:"total_tokens"`
}

type ErrorResponse struct {
	Error struct {
		Message string `json:"message"`
		Type    string `json:"type"`
		Code    string `json:"code"`
	} `json:"error"`
}

type EmbeddingService struct {
	client *generativelanguage.TextClient
	model  string
}

func NewEmbeddingService(apiKey string) (*EmbeddingService, error) {
	ctx := context.Background()

	client, err := generativelanguage.NewTextClient(ctx,
		option.WithEndpoint("https://generativelanguage.googleapis.com/v1"),
		option.WithAPIKey(apiKey),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create client: %v", err)
	}

	return &EmbeddingService{
		client: client,
		model:  "text-embedding-004", // Default model
	}, nil
}

func (s *EmbeddingService) GenerateEmbedding(ctx context.Context, input string) (*EmbeddingResponse, error) {
	req := &generativelanguagepb.EmbedTextRequest{
		Model: s.model,
		Input: []string{input},
	}

	resp, err := s.client.EmbedText(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("EmbedText error: %v", err)
	}

	if len(resp.GetResponses()) == 0 {
		return nil, fmt.Errorf("no embedding response returned")
	}

	embedding := resp.GetResponses()[0].GetEmbeddings()

	// Convert to float32 slice
	embeddingFloat32 := make([]float32, len(embedding))
	for i, val := range embedding {
		embeddingFloat32[i] = float32(val)
	}

	return &EmbeddingResponse{
		Object: "list",
		Data: []EmbeddingData{
			{
				Object:    "embedding",
				Embedding: embeddingFloat32,
				Index:     0,
			},
		},
		Model: s.model,
		Usage: EmbeddingUsage{
			PromptTokens: len(strings.Fields(input)), // Rough estimate
			TotalTokens:  len(strings.Fields(input)), // Rough estimate
		},
	}, nil
}

func (s *EmbeddingService) Close() error {
	return s.client.Close()
}

func main() {
	apiKey := os.Getenv("GOOGLE_API_KEY")
	if apiKey == "" {
		log.Fatal("GOOGLE_API_KEY environment variable is required")
	}

	// Initialize embedding service
	embedService, err := NewEmbeddingService(apiKey)
	if err != nil {
		log.Fatalf("Failed to create embedding service: %v", err)
	}
	defer embedService.Close()

	// Create router
	r := mux.NewRouter()

	// OpenAI-compatible embeddings endpoint
	r.HandleFunc("/v1/embeddings", handleEmbeddings(embedService)).Methods("POST")

	// Health check endpoint
	r.HandleFunc("/health", handleHealth).Methods("GET")

	// Start server
	port := os.Getenv("PORT")
	if port == "" {
		port = "5000"
	}

	log.Printf("Starting embedding service on port %s", port)
	log.Printf("Endpoints:")
	log.Printf("  POST /v1/embeddings - OpenAI-compatible embeddings")
	log.Printf("  GET  /health - Health check")

	log.Fatal(http.ListenAndServe(":"+port, r))
}

func handleEmbeddings(service *EmbeddingService) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Set CORS headers
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		// Parse request
		var req EmbeddingRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			sendError(w, http.StatusBadRequest, "Invalid JSON", "invalid_request")
			return
		}

		// Validate input
		if req.Input == "" {
			sendError(w, http.StatusBadRequest, "Input text is required", "invalid_request")
			return
		}

		// Generate embedding
		ctx := r.Context()
		resp, err := service.GenerateEmbedding(ctx, req.Input)
		if err != nil {
			log.Printf("Embedding generation error: %v", err)
			sendError(w, http.StatusInternalServerError, "Failed to generate embedding", "internal_error")
			return
		}

		// Send response
		w.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(w).Encode(resp); err != nil {
			log.Printf("Failed to encode response: %v", err)
		}
	}
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"status":  "healthy",
		"service": "embedding-service",
		"model":   "text-embedding-004",
	})
}

func sendError(w http.ResponseWriter, statusCode int, message, errorType string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)

	errorResp := ErrorResponse{
		Error: struct {
			Message string `json:"message"`
			Type    string `json:"type"`
			Code    string `json:"code"`
		}{
			Message: message,
			Type:    errorType,
			Code:    fmt.Sprintf("%d", statusCode),
		},
	}

	json.NewEncoder(w).Encode(errorResp)
}