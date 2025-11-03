import os
from typing import BinaryIO
from datetime import datetime

MEDIA_ROOT = os.getenv("MEDIA_ROOT", "/app/uploads")
os.makedirs(MEDIA_ROOT, exist_ok=True)

class LocalStorage:
    def save(self, fileobj: BinaryIO, filename: str) -> str:
        ts = datetime.utcnow().strftime("%Y%m%d%H%M%S%f")
        safe = filename.replace("/", "_")
        key = f"{ts}_{safe}"
        path = os.path.join(MEDIA_ROOT, key)
        with open(path, "wb") as f:
            f.write(fileobj.read())
        return key

    def open(self, key: str) -> BinaryIO:
        path = os.path.join(MEDIA_ROOT, key)
        return open(path, "rb")