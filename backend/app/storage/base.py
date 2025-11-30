from abc import ABC, abstractmethod
from typing import BinaryIO, Optional


class StorageBackend(ABC):
    @abstractmethod
    def save(self, fileobj: BinaryIO, filename: str) -> str:
        pass

    @abstractmethod
    def open(self, key: str) -> BinaryIO:
        pass

    @abstractmethod
    def delete(self, key: str) -> bool:
        pass

    def get_file_url(self, key: str) -> Optional[str]:
        return None
