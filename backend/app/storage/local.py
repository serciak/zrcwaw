import os
import re
from typing import BinaryIO, Optional
from datetime import datetime
from .base import StorageBackend

MEDIA_ROOT = os.getenv("MEDIA_ROOT", "/app/uploads")
os.makedirs(MEDIA_ROOT, exist_ok=True)


class LocalStorage(StorageBackend):
    def _sanitize(self, filename: str) -> str:
        name = os.path.basename(filename)
        return re.sub(r"[^A-Za-z0-9._-]+", "_", name) or "file"

    def save(self, fileobj: BinaryIO, filename: str) -> str:
        ts = datetime.utcnow().strftime("%Y%m%d%H%M%S%f")
        safe = self._sanitize(filename)
        key = f"{ts}_{safe}"
        path = os.path.join(MEDIA_ROOT, key)
        with open(path, "wb") as f:
            f.write(fileobj.read())
        return key

    def open(self, key: str) -> BinaryIO:
        path = os.path.join(MEDIA_ROOT, key)
        return open(path, "rb")

    def delete(self, key: str) -> bool:
        try:
            os.remove(os.path.join(MEDIA_ROOT, key))
            return True
        except FileNotFoundError:
            return False

    def get_file_url(self, key: str) -> Optional[str]:
        return f"/api/files/{key}"
