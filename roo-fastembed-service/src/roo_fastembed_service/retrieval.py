from dataclasses import dataclass
from typing import Any

import httpx
from pydantic import BaseModel, ConfigDict, Field
from qdrant_client import QdrantClient, models


class ChunkPayload(BaseModel):
    model_config = ConfigDict(extra="allow")

    repo: str | None = None
    path: str | None = None
    symbol: str | None = None
    language: str | None = None
    chunk_text: str | None = None
    start_line: int | None = None
    end_line: int | None = None
    revision: str | None = None
    chunk_hash: str | None = None


class CollectionSpec(BaseModel):
    name: str
    vector_size: int = Field(ge=1)
    distance: models.Distance = models.Distance.COSINE
    vector_name: str | None = None


class RetrievalConfig(BaseModel):
    embedding_base_url: str
    model_name: str
    collection: CollectionSpec
    qdrant_url: str
    qdrant_api_key: str | None = None
    embedding_api_key: str | None = None
    request_timeout_seconds: float = Field(default=30.0, gt=0.0)


class RetrievalResult(BaseModel):
    id: str | int | None = None
    score: float
    payload: dict[str, Any] = Field(default_factory=dict)
    chunk: ChunkPayload | None = None


@dataclass(slots=True)
class EmbeddingServiceClient:
    base_url: str
    model_name: str
    api_key: str | None = None
    timeout_seconds: float = 30.0

    def embed_texts(self, texts: list[str]) -> list[list[float]]:
        headers = self._headers()
        with httpx.Client(
            base_url=self.base_url.rstrip("/"),
            timeout=self.timeout_seconds,
        ) as client:
            response = client.post(
                "/v1/embeddings",
                json={
                    "input": texts,
                    "model": self.model_name,
                    "encoding_format": "float",
                },
                headers=headers,
            )
        response.raise_for_status()
        payload = response.json()
        return [item["embedding"] for item in payload["data"]]

    def embed_text(self, text: str) -> list[float]:
        return self.embed_texts([text])[0]

    def _headers(self) -> dict[str, str]:
        if not self.api_key:
            return {}
        return {"Authorization": f"Bearer {self.api_key}"}


class SemanticRetriever:
    def __init__(
        self,
        config: RetrievalConfig,
        *,
        embedder: EmbeddingServiceClient | None = None,
        qdrant_client: QdrantClient | None = None,
    ) -> None:
        self.config = config
        self.embedder = embedder or EmbeddingServiceClient(
            base_url=config.embedding_base_url,
            api_key=config.embedding_api_key,
            model_name=config.model_name,
            timeout_seconds=config.request_timeout_seconds,
        )
        self.qdrant = qdrant_client or QdrantClient(
            url=config.qdrant_url,
            api_key=config.qdrant_api_key,
            timeout=config.request_timeout_seconds,
        )

    def ensure_collection(self) -> None:
        collection = self.config.collection
        exists = self.qdrant.collection_exists(collection.name)
        if exists:
            info = self.qdrant.get_collection(collection.name)
            actual = info.config.params.vectors
            if isinstance(actual, dict):
                key = collection.vector_name or next(iter(actual.keys()))
                vector_params = actual[key]
            else:
                vector_params = actual

            if vector_params.size != collection.vector_size:
                raise ValueError(
                    "Configured vector size does not match existing collection "
                    f"({collection.vector_size} != {vector_params.size})"
                )
            return

        params = models.VectorParams(
            size=collection.vector_size,
            distance=collection.distance,
        )
        if collection.vector_name:
            vectors_config: models.VectorParams | dict[str, models.VectorParams] = {
                collection.vector_name: params
            }
        else:
            vectors_config = params

        self.qdrant.create_collection(
            collection_name=collection.name,
            vectors_config=vectors_config,
        )

    def search(
        self,
        query_text: str,
        *,
        limit: int = 8,
        query_filter: models.Filter | None = None,
        score_threshold: float | None = None,
    ) -> list[RetrievalResult]:
        vector = self.embedder.embed_text(query_text)
        collection = self.config.collection

        search_vector: list[float] | models.NamedVector
        if collection.vector_name:
            search_vector = models.NamedVector(
                name=collection.vector_name,
                vector=vector,
            )
        else:
            search_vector = vector

        results = self.qdrant.search(
            collection_name=collection.name,
            query_vector=search_vector,
            query_filter=query_filter,
            limit=limit,
            score_threshold=score_threshold,
            with_payload=True,
        )
        return [
            RetrievalResult(
                id=getattr(point, "id", None),
                score=float(point.score),
                payload=dict(point.payload or {}),
                chunk=ChunkPayload.model_validate(point.payload or {}),
            )
            for point in results
        ]
