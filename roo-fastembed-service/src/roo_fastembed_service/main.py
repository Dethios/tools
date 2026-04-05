import uvicorn

from roo_fastembed_service.api import create_app
from roo_fastembed_service.config import ServiceSettings


def main() -> None:
    settings = ServiceSettings()
    app = create_app(settings=settings)
    uvicorn.run(
        app,
        host=settings.host,
        port=settings.port,
        log_level=settings.log_level,
    )


if __name__ == "__main__":
    main()
