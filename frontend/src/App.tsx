import { useState, useEffect } from 'react';
import './App.css';
import { createTodo, listTodos, markComplete, uploadFile, fileUrl } from './api';
import type {Todo, TodoCreate} from './types';
import { TodoDetail } from './TodoDetail';

function App() {
  const [todos, setTodos] = useState<Todo[]>([]);
  const [loading, setLoading] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [selectedTodoId, setSelectedTodoId] = useState<number | null>(null);
  const [formData, setFormData] = useState<TodoCreate>({
    title: '',
    description: '',
    due_date: '',
    image_key: null
  });
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [filter, setFilter] = useState<'all' | 'active' | 'completed'>('all');

  useEffect(() => {
    loadTodos();
  }, []);

  async function loadTodos() {
    try {
      setLoading(true);
      const data = await listTodos();
      setTodos(data);
    } catch (error) {
      console.error('Error loading todos:', error);
      alert('Błąd podczas ładowania zadań');
    } finally {
      setLoading(false);
    }
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    if (!formData.title.trim()) {
      alert('Tytuł jest wymagany');
      return;
    }

    try {
      setUploading(true);

      let imageKey = formData.image_key;
      if (selectedFile) {
        imageKey = await uploadFile(selectedFile);
      }

      const payload: TodoCreate = {
        title: formData.title,
        description: formData.description || null,
        due_date: formData.due_date || null,
        image_key: imageKey
      };

      await createTodo(payload);
      setFormData({ title: '', description: '', due_date: '', image_key: null });
      setSelectedFile(null);
      setShowForm(false);
      await loadTodos();
    } catch (error) {
      console.error('Error creating todo:', error);
      alert('Błąd podczas tworzenia zadania');
    } finally {
      setUploading(false);
    }
  }

  async function handleComplete(todoId: number) {
    try {
      await markComplete(todoId);
      await loadTodos();
    } catch (error) {
      console.error('Error completing todo:', error);
      alert('Błąd podczas oznaczania zadania jako ukończone');
    }
  }

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    if (e.target.files && e.target.files[0]) {
      setSelectedFile(e.target.files[0]);
    }
  }

  const filteredTodos = todos.filter(todo => {
    if (filter === 'active') return !todo.completed;
    if (filter === 'completed') return todo.completed;
    return true;
  });

  const stats = {
    total: todos.length,
    active: todos.filter(t => !t.completed).length,
    completed: todos.filter(t => t.completed).length
  };

  return (
    <div className="app">
      <div className="container">
        <header className="header">
          <h1>📝 Lista Zadań</h1>
          <p className="subtitle">Zarządzaj swoimi zadaniami efektywnie</p>
        </header>

        <div className="stats">
          <div className="stat-card">
            <div className="stat-number">{stats.total}</div>
            <div className="stat-label">Wszystkie</div>
          </div>
          <div className="stat-card">
            <div className="stat-number">{stats.active}</div>
            <div className="stat-label">Aktywne</div>
          </div>
          <div className="stat-card">
            <div className="stat-number">{stats.completed}</div>
            <div className="stat-label">Ukończone</div>
          </div>
        </div>

        <div className="actions-bar">
          <div className="filter-buttons">
            <button
              className={`filter-btn ${filter === 'all' ? 'active' : ''}`}
              onClick={() => setFilter('all')}
            >
              Wszystkie
            </button>
            <button
              className={`filter-btn ${filter === 'active' ? 'active' : ''}`}
              onClick={() => setFilter('active')}
            >
              Aktywne
            </button>
            <button
              className={`filter-btn ${filter === 'completed' ? 'active' : ''}`}
              onClick={() => setFilter('completed')}
            >
              Ukończone
            </button>
          </div>
          <button
            className="add-btn"
            onClick={() => setShowForm(!showForm)}
          >
            {showForm ? '✕ Anuluj' : '+ Dodaj zadanie'}
          </button>
        </div>

        {showForm && (
          <form className="todo-form" onSubmit={handleSubmit}>
            <div className="form-group">
              <label htmlFor="title">Tytuł *</label>
              <input
                id="title"
                type="text"
                value={formData.title}
                onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                placeholder="Wpisz tytuł zadania..."
                required
              />
            </div>

            <div className="form-group">
              <label htmlFor="description">Opis</label>
              <textarea
                id="description"
                value={formData.description || ''}
                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                placeholder="Dodaj opis zadania..."
                rows={3}
              />
            </div>

            <div className="form-group">
              <label htmlFor="due_date">Termin wykonania</label>
              <input
                id="due_date"
                type="date"
                value={formData.due_date || ''}
                onChange={(e) => setFormData({ ...formData, due_date: e.target.value })}
              />
            </div>

            <div className="form-group">
              <label htmlFor="image">Załącznik obrazu</label>
              <input
                id="image"
                type="file"
                accept="image/*"
                onChange={handleFileChange}
              />
              {selectedFile && (
                <div className="file-preview">
                  📎 {selectedFile.name}
                </div>
              )}
            </div>

            <button type="submit" className="submit-btn" disabled={uploading}>
              {uploading ? 'Dodawanie...' : '✓ Dodaj zadanie'}
            </button>
          </form>
        )}

        <div className="todos-container">
          {loading ? (
            <div className="loading">Ładowanie zadań...</div>
          ) : filteredTodos.length === 0 ? (
            <div className="empty-state">
              <div className="empty-icon">📭</div>
              <p>Brak zadań do wyświetlenia</p>
            </div>
          ) : (
            <div className="todos-list">
              {filteredTodos.map(todo => (
                <div key={todo.id} className={`todo-card ${todo.completed ? 'completed' : ''}`}>
                  <div className="todo-header">
                    <div className="todo-title-section">
                      <button
                        className={`checkbox ${todo.completed ? 'checked' : ''}`}
                        onClick={() => !todo.completed && handleComplete(todo.id)}
                        disabled={todo.completed}
                      >
                        {todo.completed && '✓'}
                      </button>
                      <h3
                        className="todo-title clickable"
                        onClick={() => setSelectedTodoId(todo.id)}
                        title="Kliknij aby zobaczyć szczegóły"
                      >
                        {todo.title}
                      </h3>
                    </div>
                    {todo.completed && (
                      <span className="completed-badge">✓ Ukończono</span>
                    )}
                  </div>

                  {todo.description && (
                    <p className="todo-description">{todo.description}</p>
                  )}

                  {todo.due_date && (
                    <div className="todo-due-date">
                      📅 Termin: {new Date(todo.due_date).toLocaleDateString('pl-PL')}
                    </div>
                  )}

                  {todo.image_key && (
                    <div className="todo-image">
                      <img
                        src={fileUrl(todo.image_key)}
                        alt="Todo attachment"
                        loading="lazy"
                      />
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {selectedTodoId && (
        <TodoDetail
          todoId={selectedTodoId}
          onClose={() => setSelectedTodoId(null)}
        />
      )}
    </div>
  );
}

export default App;

