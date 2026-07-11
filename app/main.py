from contextlib import asynccontextmanager
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api.v1.api import api_router

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
    yield
    
    # Shutdown actions
    logger.info("Shutting down application...")

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
app.include_router(api_router, prefix="/api/v1")

@app.get("/")
def read_root():
    return {
        "status": "online",
        "message": "Movie Streaming Backend API is running.",
        "docs_url": "/docs"
    }
