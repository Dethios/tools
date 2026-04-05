from fastapi.testclient import TestClient

from roo_fastembed_service.api import create_app
from roo_fastembed_service.config import ServiceSettings


class FakeBackend:
    model_name = "sentence-transformers/all-MiniLM-L6-v2"

    async def embed(self, texts: list[str]) -> list[list[float]]:
        return [[float(index), float(len(text))] for index, text in enumerate(texts)]

    def vector_size(self) -> int:
        return 2


def build_client(**overrides: object) -> TestClient:
    settings = ServiceSettings(
        model_name="sentence-transformers/all-MiniLM-L6-v2",
        api_key="secret",
        expected_vector_size=2,
        max_batch_size=2,
        max_text_length=12,
        **overrides,
    )
    app = create_app(settings=settings, backend=FakeBackend())
    return TestClient(app)


def test_embeddings_success() -> None:
    client = build_client()
    response = client.post(
        "/v1/embeddings",
        headers={"Authorization": "Bearer secret"},
        json={
            "input": ["alpha", "beta"],
            "model": "sentence-transformers/all-MiniLM-L6-v2",
            "encoding_format": "float",
            "dimensions": 2,
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["model"] == "sentence-transformers/all-MiniLM-L6-v2"
    assert body["data"][0]["embedding"] == [0.0, 5.0]
    assert body["data"][1]["embedding"] == [1.0, 4.0]


def test_embeddings_rejects_wrong_model() -> None:
    client = build_client()
    response = client.post(
        "/v1/embeddings",
        headers={"Authorization": "Bearer secret"},
        json={"input": "alpha", "model": "other-model"},
    )

    assert response.status_code == 400
    assert "Unsupported model" in response.json()["detail"]


def test_embeddings_rejects_large_batch() -> None:
    client = build_client()
    response = client.post(
        "/v1/embeddings",
        headers={"Authorization": "Bearer secret"},
        json={"input": ["a", "b", "c"]},
    )

    assert response.status_code == 400
    assert "ROO_EMBED_MAX_BATCH_SIZE" in response.json()["detail"]


def test_models_requires_auth() -> None:
    client = build_client()
    response = client.get("/v1/models")

    assert response.status_code == 401
