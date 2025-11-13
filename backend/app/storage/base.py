from abc import ABC, abstractmethod
from typing import BinaryIO, Optional


class StorageBackend(ABC):
    @abstractmethod
    def save(self, fileobj: BinaryIO, filename: str) -> str:
        """Zapisz plik i zwróć jego klucz"""
        pass

    @abstractmethod
    def open(self, key: str) -> BinaryIO:
        """Otwórz plik do odczytu binarnego"""
        pass

    @abstractmethod
    def delete(self, key: str) -> bool:
        """Usuń plik"""
        pass

    def get_file_url(self, key: str) -> Optional[str]:
        """Zwróć zewnętrzny URL (np. pre-signed). Dla lokalnego storage może zwrócić None."""
        return None
