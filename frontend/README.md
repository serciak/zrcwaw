# Todo App - Frontend

Nowoczesna aplikacja do zarządzania zadaniami z pięknym interfejsem użytkownika.

## ✨ Funkcje

### Pełna integracja z API
- ✅ **GET /api/todos/** - Lista wszystkich zadań
- ✅ **POST /api/todos/** - Tworzenie nowego zadania
- ✅ **GET /api/todos/{id}** - Szczegóły pojedynczego zadania
- ✅ **POST /api/todos/{id}/complete** - Oznaczanie zadania jako ukończone
- ✅ **POST /api/files/** - Upload plików/obrazów
- ✅ **GET /api/files/{key}** - Pobieranie plików

### Funkcjonalności UI
- 📊 **Statystyki** - Podsumowanie wszystkich, aktywnych i ukończonych zadań
- 🔍 **Filtrowanie** - Wyświetlanie wszystkich, aktywnych lub ukończonych zadań
- ➕ **Dodawanie zadań** - Formularz z tytułem, opisem, terminem i obrazem
- ✓ **Oznaczanie jako ukończone** - Jednym kliknięciem
- 👁️ **Szczegóły zadania** - Modal z pełnymi informacjami (kliknij tytuł)
- 📎 **Załączniki obrazów** - Upload i wyświetlanie obrazów
- 🎨 **Responsywny design** - Działa na wszystkich urządzeniach

## 🚀 Uruchomienie

### Wymagania
- Node.js 18+
- npm lub yarn

### Instalacja i uruchomienie

```bash
# Instalacja zależności
npm install

# Uruchomienie w trybie deweloperskim
npm run dev

# Build produkcyjny
npm run build
```

### Konfiguracja

Ustaw zmienną środowiskową `VITE_API_URL` w pliku `.env`:

```
VITE_API_URL=http://localhost:8000
```

## 🎨 Design

Aplikacja wykorzystuje nowoczesny design z:
- Gradientowym tłem (purple-blue)
- Kartami z cieniami i animacjami
- Responsywnymi komponentami
- Intuicyjnymi ikonami
- Płynnymi przejściami

## 📱 Responsywność

Aplikacja jest w pełni responsywna i dostosowuje się do:
- 📱 Smartfonów
- 💻 Tabletów  
- 🖥️ Desktopów

## 🛠️ Technologie

- **React 18** - Biblioteka UI
- **TypeScript** - Typowanie
- **Axios** - Komunikacja z API
- **Vite** - Build tool
- **CSS3** - Stylowanie z animacjami

