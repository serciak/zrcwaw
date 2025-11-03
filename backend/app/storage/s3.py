import os
import boto3
from typing import BinaryIO
from .base import StorageBackend


class S3Storage(StorageBackend):
    def __init__(self):
        self.bucket_name = os.getenv("AWS_S3_BUCKET_NAME")
        self.region = os.getenv("AWS_REGION", "us-east-1")
        self.s3_client = boto3.client('s3', region_name=self.region)

    async def upload_file(self, file: BinaryIO, key: str) -> str:
        self.s3_client.upload_fileobj(file, self.bucket_name, key)
        return key

    async def get_file_url(self, key: str) -> str:
        return f"https://{self.bucket_name}.s3.{self.region}.amazonaws.com/{key}"

    async def delete_file(self, key: str) -> bool:
        try:
            self.s3_client.delete_object(Bucket=self.bucket_name, Key=key)
            return True
        except Exception:
            return False

