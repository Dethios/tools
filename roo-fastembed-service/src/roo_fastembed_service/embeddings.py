import asyncio
from dataclasses import dataclass
from typing import Any, Protocol

from roo_fastembed_service.config import ServiceSettings


class EmbeddingBackend(Protocol):
    model_name: str

    async def embed(self, texts: list[str]) -> list[list[float]]:
        ...

    def vector_size(self) -> int:
        ...


@dataclass(slots=True)
class FastEmbedBackend:
    model_name: str

    def __post_init__(self) -> None:
        from fastembed import TextEmbedding

        self._embedding_model = TextEmbedding(model_name=self.model_name)

    async def embed(self, texts: list[str]) -> list[list[float]]:
        loop = asyncio.get_running_loop()
        vectors = await loop.run_in_executor(
            None,
            lambda: list(self._embedding_model.embed(texts)),
        )
        return [vector.tolist() for vector in vectors]

    def vector_size(self) -> int:
        description: Any = self._embedding_model._get_model_description(self.model_name)
        return int(description.dim)


def build_backend(settings: ServiceSettings) -> FastEmbedBackend:
    backend = FastEmbedBackend(model_name=settings.model_name)
    if (
        settings.expected_vector_size is not None
        and backend.vector_size() != settings.expected_vector_size
    ):
        raise ValueError(
            "Configured ROO_EMBED_EXPECTED_VECTOR_SIZE does not match model output "
            f"({settings.expected_vector_size} != {backend.vector_size()})"
        )
    return backend
