from sqlalchemy import Column, Integer, String, Boolean, DateTime, Text
from sqlalchemy.sql import func
from .database import Base

class Todo(Base):
    __tablename__ = "todos"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)
    due_date = Column(String(32), nullable=True)
    completed = Column(Boolean, default=False)
    image_key = Column(String(512), nullable=True)
    user_id = Column(String(36), index=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

