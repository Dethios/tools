# roo-fastembed-service

Small OpenAI-compatible embeddings service over FastEmbed plus a direct Qdrant retrieval module.

This tool is intended to be the shared semantic contract for:

- Roo Code indexing via an OpenAI-compatible embeddings endpoint
- direct service-to-service retrieval from other agents and CLI tools
- optional MCP adapters that should point at the same Qdrant collection policy

## What it provides

- `GET /health`
- `GET /v1/models`
- `POST /v1/embeddings`
- `EmbeddingServiceClient` for deterministic query embedding through the wrapper
- `SemanticRetriever` for direct `qdrant-client` retrieval using the returned vector
- `ChunkPayload` and `CollectionSpec` helpers to keep collection metadata consistent

## Install

From this directory:

```bash
python3 -m pip install -e .
```

Or install dependencies into an existing virtual environment and launch through the root wrapper:

```bash
./scripts/serve-roo-embeddings.sh
```

## Configuration

The service is intentionally single-model by default. Treat the model, vector size, and collection schema as immutable until you deliberately re-index into a new collection version.

### Service environment variables

| Variable                         | Default                                  | Purpose                                                                      |
| -------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------- |
| `ROO_EMBED_MODEL`                | `sentence-transformers/all-MiniLM-L6-v2` | Pinned FastEmbed model served by the API                                     |
| `ROO_EMBED_API_KEY`              | unset                                    | Optional bearer token required on `GET /v1/models` and `POST /v1/embeddings` |
| `ROO_EMBED_EXPECTED_VECTOR_SIZE` | unset                                    | Optional startup assertion for the model output dimension                    |
| `ROO_EMBED_MAX_BATCH_SIZE`       | `64`                                     | Maximum number of input strings per request                                  |
| `ROO_EMBED_MAX_TEXT_LENGTH`      | `20000`                                  | Maximum characters per input string                                          |
| `ROO_EMBED_HOST`                 | `127.0.0.1`                              | Bind host                                                                    |
| `ROO_EMBED_PORT`                 | `8108`                                   | Bind port                                                                    |
| `ROO_EMBED_LOG_LEVEL`            | `info`                                   | Uvicorn log level                                                            |
| `ROO_EMBED_ALLOW_CORS`           | `false`                                  | Allow all origins for local browser testing                                  |

### Retrieval settings

Recommended collection naming:

- `repo_semantic_v1`
- `repo_semantic_v2` when model, dimension, distance metric, or chunk schema changes

Recommended payload fields are captured by `ChunkPayload`:

- `repo`
- `path`
- `symbol`
- `language`
- `chunk_text`
- `start_line`
- `end_line`
- `revision`
- `chunk_hash`

## Roo configuration

Point Roo codebase indexing at:

- Embedder provider: OpenAI compatible
- Base URL: `http://127.0.0.1:8108`
- Model: the pinned `ROO_EMBED_MODEL`
- Embedding dimension: the exact model output dimension
- Qdrant URL: your shared Qdrant instance
- Collection: a deliberate versioned collection such as `repo_semantic_v1`

## Python usage

### Run the service

```bash
export ROO_EMBED_MODEL="sentence-transformers/all-MiniLM-L6-v2"
export ROO_EMBED_API_KEY="change-me"
./scripts/serve-roo-embeddings.sh
```

### Query through the wrapper and search Qdrant directly

```python
from roo_fastembed_service.retrieval import CollectionSpec, RetrievalConfig, SemanticRetriever

config = RetrievalConfig(
    embedding_base_url="http://127.0.0.1:8108",
    embedding_api_key="change-me",
    model_name="sentence-transformers/all-MiniLM-L6-v2",
    collection=CollectionSpec(
        name="repo_semantic_v1",
        vector_size=384,
    ),
    qdrant_url="http://127.0.0.1:6333",
)

retriever = SemanticRetriever(config)
results = retriever.search("where is the task packet schema defined?", limit=5)
for item in results:
    print(item.score, item.payload.get("path"))
```

## Validation

Run from this directory:

```bash
python3 -m pytest
```

If dependencies are not installed yet, install them first:

```bash
python3 -m pip install -e .
```
