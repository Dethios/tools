import logging
from typing import Annotated, Any

from fastapi import Depends, FastAPI, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, model_validator

from roo_fastembed_service.config import ServiceSettings
from roo_fastembed_service.embeddings import EmbeddingBackend, build_backend

logger = logging.getLogger(__name__)


class EmbeddingRequest(BaseModel):
    input: str | list[str]
    model: str | None = None
    encoding_format: str = "float"
    dimensions: int | None = None
    user: str | None = None

    @model_validator(mode="after")
    def validate_input(self) -> "EmbeddingRequest":
        if isinstance(self.input, list) and not self.input:
            raise ValueError("input must not be an empty list")
        return self


class EmbeddingResponseItem(BaseModel):
    object: str = "embedding"
    index: int
    embedding: list[float]


class EmbeddingResponse(BaseModel):
    object: str = "list"
    data: list[EmbeddingResponseItem]
    model: str
    usage: dict[str, int]


def _authorize(
    authorization: Annotated[str | None, Header()] = None,
    settings: ServiceSettings | None = None,
) -> None:
    if settings is None or not settings.api_key:
        return
    if authorization != f"Bearer {settings.api_key}":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized",
        )


def create_app(
    settings: ServiceSettings | None = None,
    backend: EmbeddingBackend | None = None,
) -> FastAPI:
    settings = settings or ServiceSettings()
    backend = backend or build_backend(settings)

    app = FastAPI(title="roo-fastembed-service", version="0.1.0")
    app.state.settings = settings
    app.state.backend = backend
    app.state.embedding_requests = 0

    if settings.allow_cors:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    def require_auth(
        authorization: Annotated[str | None, Header()] = None,
    ) -> None:
        _authorize(authorization=authorization, settings=settings)

    @app.get("/health")
    async def health() -> dict[str, Any]:
        return {
            "status": "ok",
            "model": settings.model_name,
            "vector_size": backend.vector_size(),
            "max_batch_size": settings.max_batch_size,
            "embedding_requests": app.state.embedding_requests,
        }

    @app.get("/v1/models", dependencies=[Depends(require_auth)])
    async def list_models() -> dict[str, Any]:
        return {
            "object": "list",
            "data": [
                {
                    "id": settings.model_name,
                    "object": "model",
                    "owned_by": "internal",
                    "metadata": {
                        "vector_size": backend.vector_size(),
                    },
                }
            ],
        }

    @app.post(
        "/v1/embeddings",
        response_model=EmbeddingResponse,
        dependencies=[Depends(require_auth)],
    )
    async def create_embeddings(request: EmbeddingRequest) -> EmbeddingResponse:
        if request.model and request.model != settings.model_name:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Unsupported model: {request.model}",
            )
        if request.encoding_format != "float":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Only encoding_format=float is supported",
            )
        if request.dimensions is not None and request.dimensions != backend.vector_size():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    "Requested dimensions do not match the pinned model output "
                    f"({request.dimensions} != {backend.vector_size()})"
                ),
            )

        texts = request.input if isinstance(request.input, list) else [request.input]
        if len(texts) > settings.max_batch_size:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=(
                    f"Batch size {len(texts)} exceeds ROO_EMBED_MAX_BATCH_SIZE="
                    f"{settings.max_batch_size}"
                ),
            )

        for index, text in enumerate(texts):
            if len(text) > settings.max_text_length:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=(
                        f"Input at index {index} exceeds ROO_EMBED_MAX_TEXT_LENGTH="
                        f"{settings.max_text_length}"
                    ),
                )

        vectors = await backend.embed(texts)
        app.state.embedding_requests += 1
        logger.info(
            "served embedding batch",
            extra={
                "model": settings.model_name,
                "vector_size": backend.vector_size(),
                "batch_size": len(texts),
                "request_count": app.state.embedding_requests,
            },
        )
        data = [
            EmbeddingResponseItem(index=index, embedding=vector)
            for index, vector in enumerate(vectors)
        ]
        return EmbeddingResponse(
            data=data,
            model=settings.model_name,
            usage={"prompt_tokens": 0, "total_tokens": 0},
        )

    return app
