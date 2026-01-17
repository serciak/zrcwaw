import os
import re
import mimetypes
from io import BytesIO
from typing import BinaryIO, Optional
import boto3
from botocore.exceptions import ClientError
from botocore.config import Config
from .base import StorageBackend


class S3Storage(StorageBackend):
    """S3-compatible storage backend (works with AWS S3 and MinIO)"""

    def __init__(self):
        self.bucket = os.getenv("S3_BUCKET_NAME")
        if not self.bucket:
            raise RuntimeError("Brak S3_BUCKET_NAME/AWS_S3_BUCKET_NAME")

        self.region = os.getenv("AWS_REGION", "us-east-1")
        self.endpoint_url = os.getenv("S3_ENDPOINT_URL")  # For MinIO
        self.access_key = os.getenv("S3_ACCESS_KEY", os.getenv("AWS_ACCESS_KEY_ID"))
        self.secret_key = os.getenv("S3_SECRET_KEY", os.getenv("AWS_SECRET_ACCESS_KEY"))
        self.public_endpoint_url = os.getenv("S3_PUBLIC_ENDPOINT_URL", self.endpoint_url)
        self.verify_ssl = os.getenv("SSL_VERIFY", "true").lower() not in ("false", "0", "no")

        # Create boto3 client with optional custom endpoint
        client_kwargs = {
            "region_name": self.region,
            "config": Config(signature_version='s3v4'),
            "verify": self.verify_ssl
        }

        if self.endpoint_url:
            client_kwargs["endpoint_url"] = self.endpoint_url

        if self.access_key and self.secret_key:
            client_kwargs["aws_access_key_id"] = self.access_key
            client_kwargs["aws_secret_access_key"] = self.secret_key

        self.s3 = boto3.client("s3", **client_kwargs)
        self.expires = int(os.getenv("S3_URL_EXPIRES", "900"))  # 15 min

        # Ensure bucket exists (for MinIO)
        self._ensure_bucket_exists()

    def _sanitize(self, filename: str) -> str:
        name = os.path.basename(filename)
        return re.sub(r"[^A-Za-z0-9._-]+", "_", name) or "file"

    def _ensure_bucket_exists(self):
        """Create bucket if it doesn't exist (useful for MinIO)"""
        try:
            self.s3.head_bucket(Bucket=self.bucket)
        except ClientError as e:
            error_code = e.response.get("Error", {}).get("Code")
            if error_code in ("404", "NoSuchBucket"):
                try:
                    if self.region == "us-east-1":
                        self.s3.create_bucket(Bucket=self.bucket)
                    else:
                        self.s3.create_bucket(
                            Bucket=self.bucket,
                            CreateBucketConfiguration={"LocationConstraint": self.region}
                        )
                except ClientError:
                    pass  # Bucket may already exist or we don't have permissions

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
        # Generate presigned URL
        url = self.s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": self.bucket, "Key": key},
            ExpiresIn=self.expires,
        )

        # If using MinIO with different public endpoint, replace the URL
        if self.public_endpoint_url and self.endpoint_url and self.public_endpoint_url != self.endpoint_url:
            url = url.replace(self.endpoint_url, self.public_endpoint_url)

        return url
