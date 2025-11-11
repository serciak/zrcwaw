from sqlalchemy.orm import Session
from .models import Todo
from .schemas import TodoCreate

def create_todo(db: Session, data: TodoCreate, user_id: str) -> Todo:
    obj = Todo(
        title=data.title,
        description=data.description,
        due_date=data.due_date,
        image_key=data.image_key,
        completed=False,
        user_id=user_id,
    )
    db.add(obj)
    db.commit()
    db.refresh(obj)
    return obj

def list_todos(db: Session, user_id: int):
    return db.query(Todo).filter(Todo.user_id == user_id).order_by(Todo.id.desc()).all()

def get_todo(db: Session, todo_id: int, user_id: int):
    return db.query(Todo).filter(Todo.id == todo_id, Todo.user_id == user_id).first()

def toggle_done(db: Session, todo_id: int, completed: bool, user_id: int):
    obj = get_todo(db, todo_id, user_id)
    if not obj:
        return None
    obj.completed = completed
    db.commit()
    db.refresh(obj)
    return obj