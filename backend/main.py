from contextlib import asynccontextmanager
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from backend.session import init_session, close_session
from backend.routes import movies, streams

# Setup basic logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup actions
    logger.info("Initializing application startup...")
    
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

@app.get("/")
def read_root():
    return {
        "status": "online",
        "message": "Movie Streaming Backend API is running.",
        "docs_url": "/docs"
    }
