from types import SimpleNamespace

from qdrant_client import models

from roo_fastembed_service.retrieval import (
    CollectionSpec,
    EmbeddingServiceClient,
    RetrievalConfig,
    SemanticRetriever,
)


class FakeEmbedder(EmbeddingServiceClient):
    def __init__(self) -> None:
        pass

    def embed_text(self, text: str) -> list[float]:
        assert text == "find task packet schema"
        return [0.1, 0.2, 0.3]


class FakeQdrantClient:
    def __init__(self) -> None:
        self.search_calls = []

    def search(self, **kwargs):
        self.search_calls.append(kwargs)
        return [
            SimpleNamespace(
                id="p1",
                score=0.91,
                payload={
                    "repo": "dev-workspace",
                    "path": "manifests/task-packet.schema.yaml",
                    "chunk_text": "title: Roo to Codex Task Packet",
                    "start_line": 1,
                    "end_line": 5,
                },
            )
        ]


def test_semantic_retriever_uses_wrapper_vector_for_qdrant_search() -> None:
    config = RetrievalConfig(
        embedding_base_url="http://127.0.0.1:8108",
        embedding_api_key="secret",
        model_name="sentence-transformers/all-MiniLM-L6-v2",
        collection=CollectionSpec(
            name="repo_semantic_v1",
            vector_size=3,
            vector_name="code",
        ),
        qdrant_url="http://127.0.0.1:6333",
    )
    qdrant = FakeQdrantClient()
    retriever = SemanticRetriever(
        config,
        embedder=FakeEmbedder(),
        qdrant_client=qdrant,
    )

    results = retriever.search("find task packet schema", limit=4)

    assert len(results) == 1
    assert results[0].payload["path"] == "manifests/task-packet.schema.yaml"
    assert qdrant.search_calls[0]["limit"] == 4
    query_vector = qdrant.search_calls[0]["query_vector"]
    assert isinstance(query_vector, models.NamedVector)
    assert query_vector.name == "code"
    assert query_vector.vector == [0.1, 0.2, 0.3]
