from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from ..database import get_db
from .. import crud, schemas

router = APIRouter(prefix="/api/todos", tags=["todos"])

@router.get("/", response_model=list[schemas.TodoOut])
def list_all(db: Session = Depends(get_db)):
    return crud.list_todos(db)

@router.get("/{todo_id}", response_model=schemas.TodoOut)
def get_one(todo_id: int, db: Session = Depends(get_db)):
    obj = crud.get_todo(db, todo_id)
    if not obj:
        raise HTTPException(404, "Todo not found")
    return obj

@router.post("/", response_model=schemas.TodoOut)
def create(data: schemas.TodoCreate, db: Session = Depends(get_db)):
    return crud.create_todo(db, data)

@router.post("/{todo_id}/complete", response_model=schemas.TodoOut)
def mark_complete(todo_id: int, db: Session = Depends(get_db)):
    obj = crud.toggle_done(db, todo_id, True)
    if not obj:
        raise HTTPException(404, "Todo not found")
    return obj