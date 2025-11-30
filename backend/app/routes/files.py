import os
import mimetypes
from io import BytesIO
from fastapi import APIRouter, UploadFile, File, HTTPException, Response, Depends
from fastapi.responses import RedirectResponse

from ..auth import get_current_user
from ..storage.local import LocalStorage

router = APIRouter(prefix="/api/files", tags=["files"])

USE_S3 = bool(os.getenv("S3_BUCKET_NAME"))
if USE_S3:
    from ..storage.s3 import S3Storage
    storage = S3Storage()
else:
    storage = LocalStorage()

@router.post("/", summary="Upload file")
async def upload_file(file: UploadFile = File(...), current_user = Depends(get_current_user)):
    content = await file.read()
    key = storage.save(BytesIO(content), file.filename)

    url = storage.get_file_url(key) or f"/api/files/{key}"
    return {"key": key, "url": url}

@router.get("/{key}", summary="Download file or redirect to S3")
def download_file(key: str):
    if USE_S3:
        url = storage.get_file_url(key)
        if not url:
            raise HTTPException(status_code=404, detail="File not found")
        return RedirectResponse(url=url, status_code=307)

    try:
        f = storage.open(key)
        data = f.read()
        f.close()
        content_type = mimetypes.guess_type(key)[0] or "application/octet-stream"
        headers = {}
        if not content_type.startswith("image/"):
            headers["Content-Disposition"] = f'attachment; filename="{key}"'
        return Response(content=data, media_type=content_type, headers=headers)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="File not found")
