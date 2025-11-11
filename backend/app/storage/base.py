from abc import ABC, abstractmethod
from typing import BinaryIO


class StorageBackend(ABC):
    @abstractmethod
    async def upload_file(self, file: BinaryIO, key: str) -> str:
        """Upload a file and return its key/identifier"""
        pass

    @abstractmethod
    async def get_file_url(self, key: str) -> str:
        """Get the URL to access a file"""
        pass

    @abstractmethod
    async def delete_file(self, key: str) -> bool:
        """Delete a file"""
        pass
