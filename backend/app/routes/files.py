from fastapi import APIRouter, UploadFile, File, HTTPException, Response
from ..storage.local import LocalStorage
from io import BytesIO

router = APIRouter(prefix="/api/files", tags=["files"])
storage = LocalStorage()

@router.post("/", summary="Upload file (image)")
async def upload_file(file: UploadFile = File(...)):
    key = storage.save(BytesIO(await file.read()), file.filename)
    return {"key": key}

@router.get("/{key}", summary="Download file")
def download_file(key: str):
    try:
        f = storage.open(key)
        data = f.read()
        f.close()
        return Response(content=data, media_type="application/octet-stream")
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="File not found")