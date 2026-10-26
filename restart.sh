#!/bin/bash
echo "Перезапуск проекта..."

# 1. Освобождаем порты гарантированно (игнорируем ошибки, если порты и так свободны)
sudo fuser -k 3000/tcp 2>/dev/null || true
sudo fuser -k 8000/tcp 2>/dev/null || true
pkill -f "manage.py runserver" 2>/dev/null || true

# Небольшая пауза, чтобы ОС успела освободить ресурсы
sleep 1

# 2. Получаем абсолютный путь к директории скрипта
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 3. Запуск Backend
echo "Запуск Backend (порт 8000)..."
cd "$PROJECT_ROOT/backend" || exit
if [ -f "../venv/bin/activate" ]; then
    source ../venv/bin/activate
fi
python manage.py runserver 8000 > ../backend.log 2>&1 &
BACKEND_PID=$!

# 4. Запуск Frontend
echo "Запуск Frontend (порт 3000)..."
cd "$PROJECT_ROOT/frontend" || exit
npm start > ../frontend.log 2>&1 &
FRONTEND_PID=$!

# 5. Возвращаемся в корень
cd "$PROJECT_ROOT"

echo "=================================================="
echo "✅ Проект успешно перезапущен!"
echo "📌 Backend PID:  $BACKEND_PID"
echo "📌 Frontend PID: $FRONTEND_PID"
echo "=================================================="
echo "💡 Чтобы остановить проект, выполните:"
echo "   ./stop.sh"
echo "   (или sudo fuser -k 3000/tcp 8000/tcp)"
