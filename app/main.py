import os

from fastapi import FastAPI

app = FastAPI()

# Injected at build time (docker build --build-arg APP_VERSION=<commit sha>)
VERSION = os.getenv("APP_VERSION", "dev")


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/version")
def version():
    return {"version": VERSION}
