import { useState, useEffect } from 'react';
import type {Todo} from './types';
import {getTodo, fileUrl, isImageKey} from './api';
import './TodoDetail.css';

interface TodoDetailProps {
  todoId: number;
  onClose: () => void;
}

export function TodoDetail({ todoId, onClose }: TodoDetailProps) {
  const [todo, setTodo] = useState<Todo | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isOpen, setIsOpen] = useState(true);

  useEffect(() => {
    async function loadTodo() {
      try {
        setLoading(true);
        setError(null);
        const data = await getTodo(todoId);
        setTodo(data);
      } catch (err) {
        setError('Nie udało się załadować szczegółów zadania');
        console.error('Error loading todo:', err);
      } finally {
        setLoading(false);
      }
    }

    loadTodo();
  }, [todoId]);

  function handleClose() {
    setIsOpen(false);
    setTimeout(onClose, 300);
  }

  if (!isOpen) return null;

  return (
    <div className={`modal-overlay ${isOpen ? 'open' : ''}`} onClick={handleClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <button className="modal-close" onClick={handleClose}>✕</button>

        {loading && <div className="modal-loading">Ładowanie...</div>}

        {error && <div className="modal-error">{error}</div>}

        {todo && (
          <div className="todo-detail">
            <div className="detail-header">
              <h2>{todo.title}</h2>
              {todo.completed && (
                <span className="status-badge completed">✓ Ukończone</span>
              )}
              {!todo.completed && (
                <span className="status-badge active">⏳ Aktywne</span>
              )}
            </div>

            {todo.description && (
              <div className="detail-section">
                <h3>Opis</h3>
                <p>{todo.description}</p>
              </div>
            )}

            {todo.due_date && (
              <div className="detail-section">
                <h3>Termin</h3>
                <p>📅 {new Date(todo.due_date).toLocaleDateString('pl-PL', {
                  year: 'numeric',
                  month: 'long',
                  day: 'numeric'
                })}</p>
              </div>
            )}

            {todo.image_key && (
              <div className="detail-section">
                <h3>Załącznik</h3>
                <a href={fileUrl(todo.image_key)} download target="_blank" rel="noopener noreferrer" style={{ textDecoration: "none" }}>
                    {isImageKey(todo.image_key) ? (
                        <img src={fileUrl(todo.image_key)} alt="Todo attachment" loading="lazy" className="detail-image"/>
                    ) : (
                        <div className="todo-attachment">
                            📎 Załącznik
                        </div>
                    )}
                </a>
              </div>
            )}

            <div className="detail-meta">
              <small>ID zadania: #{todo.id}</small>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
