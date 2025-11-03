from pydantic import BaseModel
from typing import Optional

class TodoCreate(BaseModel):
    title: str
    description: Optional[str] = None
    due_date: Optional[str] = None
    image_key: Optional[str] = None

class TodoOut(BaseModel):
    id: int
    title: str
    description: Optional[str]
    due_date: Optional[str]
    completed: bool
    image_key: Optional[str]

    class Config:
        from_attributes = True

