import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .database import engine, Base
from .routes import todos, files

Base.metadata.create_all(bind=engine)

app = FastAPI(title="Todo API (AWS-ready)")

origins = os.getenv("ALLOWED_ORIGINS", "*").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(todos.router)
app.include_router(files.router)

@app.get("/health")
def health():
    return {"status": "ok"}