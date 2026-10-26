
#!/bin/bash
echo "Остановка проекта..."

# Освобождаем порты
sudo fuser -k 3000/tcp 2>/dev/null || true
sudo fuser -k 8000/tcp 2>/dev/null || true
pkill -f "manage.py runserver" 2>/dev/null || true

# Останавливаем Docker контейнер с БД
sudo docker compose stop postgres 2>/dev/null || true

echo "Проект остановлен. Порты 3000 и 8000 свободны."
