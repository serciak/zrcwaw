import os
import re
import mimetypes
from io import BytesIO
from typing import BinaryIO, Optional
import boto3
from botocore.exceptions import ClientError
from .base import StorageBackend


class S3Storage(StorageBackend):
    def __init__(self):
        self.bucket = os.getenv("S3_BUCKET_NAME")
        if not self.bucket:
            raise RuntimeError("Brak S3_BUCKET_NAME/AWS_S3_BUCKET_NAME")
        self.region = os.getenv("AWS_REGION")
        self.s3 = boto3.client("s3", region_name=self.region)
        self.expires = int(os.getenv("S3_URL_EXPIRES", "900"))  # 15 min

    def _sanitize(self, filename: str) -> str:
        name = os.path.basename(filename)
        return re.sub(r"[^A-Za-z0-9._-]+", "_", name) or "file"

    def save(self, fileobj: BinaryIO, filename: str) -> str:
        key = self._sanitize(filename)
        content_type = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        fileobj.seek(0)
        self.s3.put_object(Bucket=self.bucket, Key=key, Body=fileobj.read(), ContentType=content_type)
        return key

    def open(self, key: str) -> BinaryIO:
        try:
            obj = self.s3.get_object(Bucket=self.bucket, Key=key)
            data = obj["Body"].read()
            return BytesIO(data)
        except ClientError as e:
            code = e.response.get("Error", {}).get("Code")
            if code in ("NoSuchKey", "NotFound"):
                raise FileNotFoundError(key)
            raise

    def delete(self, key: str) -> bool:
        self.s3.delete_object(Bucket=self.bucket, Key=key)
        return True

    def get_file_url(self, key: str) -> Optional[str]:
        return self.s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=self.expires,
        )
