from contextlib import asynccontextmanager
import logging
import time
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from backend.logger import setup_logging, http_log
from backend.session import init_session, close_session
from backend.services.cache_db import init_cache_db, purge_expired_cache
from backend.routes import movies, streams, subtitles

# Initialize custom clean, colored logging
setup_logging()
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup actions
    logger.info("Initializing application startup...")
    init_cache_db()
    purge_expired_cache()
    
    await init_session()
    yield
    
    # Shutdown actions
    logger.info("Shutting down application...")
    await close_session()

app = FastAPI(
    title="Movie Streaming Backend API",
    description="A lightweight backend for movie search and streaming link scraper.",
    version="1.0.0",
    lifespan=lifespan
)

# Custom Request Duration Logger Middleware
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    duration_ms = (time.perf_counter() - start) * 1000

    path = request.url.path
    if not path.startswith("/docs") and not path.startswith("/openapi") and path != "/favicon.ico":
        if request.url.query:
            path = f"{path}?{request.url.query}"
        logger.info(http_log(request.method, path, response.status_code, duration_ms))

    return response

# Enable CORS for local app development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount API routes
app.include_router(movies.router, prefix="/api/v1/movies", tags=["movies"])
app.include_router(streams.router, prefix="/api/v1/streams", tags=["streams"])
app.include_router(subtitles.router, prefix="/api/v1/subtitles", tags=["subtitles"])

@app.get("/")
def read_root():
    return {
        "status": "online",
        "message": "Movie Streaming Backend API is running.",
        "docs_url": "/docs"
    }
