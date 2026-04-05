from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class ServiceSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="ROO_EMBED_",
        extra="ignore",
    )

    model_name: str = Field(default="sentence-transformers/all-MiniLM-L6-v2")
    api_key: str | None = Field(default=None)
    expected_vector_size: int | None = Field(default=None)
    max_batch_size: int = Field(default=64, ge=1)
    max_text_length: int = Field(default=20000, ge=1)
    host: str = Field(default="127.0.0.1")
    port: int = Field(default=8108, ge=1, le=65535)
    log_level: str = Field(default="info")
    allow_cors: bool = Field(default=False)
