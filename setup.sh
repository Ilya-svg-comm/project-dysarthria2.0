#!/bin/bash

# ============================================================
# Скрипт автоматического развёртывания Project Dysarthria
# Использование: ./setup.sh
# ============================================================

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции вывода
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Функция проверки команды
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Функция интерактивного вопроса
ask_install() {
    local package="$1"
    local install_cmd="$2"
    log_warn "Пакет '$package' не найден. Установить? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        log_info "Установка $package..."
        eval "$install_cmd"
        log_success "$package установлен"
    else
        log_error "Для работы проекта необходим $package. Выход."
        exit 1
    fi
}


#=============================================================
# Шаг 0: Сделать скрипты исполняемые
#=============================================================

chmod +x stop.sh
chmod +x restart.sh

# ============================================================
# ШАГ 1: Проверка и установка системных зависимостей
# ============================================================
log_info "=== Шаг 1: Проверка системных зависимостей ==="

# Python3
if ! check_command python3; then
    ask_install "python3" "sudo apt-get update && sudo apt-get install -y python3 python3-venv python3-pip"
fi

# Node.js и npm
if ! check_command node; then
    ask_install "nodejs" "sudo apt-get update && sudo apt-get install -y nodejs npm"
fi

if ! check_command npm; then
    ask_install "npm" "sudo apt-get update && sudo apt-get install -y npm"
fi

# Docker
if ! check_command docker; then
    ask_install "docker" "sudo apt-get update && sudo apt-get install -y docker.io"
    sudo systemctl enable docker
    sudo systemctl start docker
fi

# Docker Compose plugin
if ! docker compose version >/dev/null 2>&1; then
    log_warn "Docker Compose plugin не найден. Установить? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        log_info "Установка Docker Compose plugin..."
        sudo mkdir -p /usr/local/lib/docker/cli-plugins
        sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
            -o /usr/local/lib/docker/cli-plugins/docker-compose
        sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
        log_success "Docker Compose plugin установлен"
    else
        log_error "Docker Compose необходим для работы проекта. Выход."
        exit 1
    fi
fi

# Yarn (опционально, можно использовать npm)
if ! check_command yarn; then
    log_warn "Yarn не найден. Использовать npm вместо yarn? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        USE_YARN=false
        log_info "Будет использоваться npm"
    else
        ask_install "yarn" "sudo npm install -g yarn"
        USE_YARN=true
    fi
else
    USE_YARN=true
fi

# ============================================================
# ШАГ 2: Проверка прав Docker
# ============================================================
log_info "=== Шаг 2: Проверка прав Docker ==="

if ! docker ps >/dev/null 2>&1; then
    log_warn "Нет прав для управления Docker без sudo. Добавить пользователя '$USER' в группу docker? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo usermod -aG docker "$USER"
        log_success "Пользователь добавлен в группу docker"
        log_warn "Для применения изменений нужно перезайти в систему или выполнить: newgrp docker"
        log_info "Продолжаю с sudo..."
        DOCKER_CMD="sudo docker"
    else
        DOCKER_CMD="sudo docker"
    fi
else
    DOCKER_CMD="docker"
    log_success "Права Docker настроены"
fi

# ============================================================
# ШАГ 3: Проверка порта 5432
# ============================================================
log_info "=== Шаг 3: Проверка порта 5432 ==="

if ss -tulnp 2>/dev/null | grep -q ":5432 "; then
    log_warn "Порт 5432 занят. Возможно, запущен локальный PostgreSQL."
    log_warn "Остановить локальный PostgreSQL? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        sudo systemctl stop postgresql 2>/dev/null || true
        sudo systemctl disable postgresql 2>/dev/null || true
        log_success "Локальный PostgreSQL остановлен"
    else
        log_error "Порт 5432 необходим для базы данных проекта. Выход."
        exit 1
    fi
else
    log_success "Порт 5432 свободен"
fi

# ============================================================
# ШАГ 4: Создание файлов окружения
# ============================================================
log_info "=== Шаг 4: Создание файлов окружения ==="

# .env.docker
if [ ! -f ".env.docker" ]; then
    log_info "Создание .env.docker..."
    cat <<EOF > .env.docker
POSTGRES_DB=project-db
POSTGRES_USER=user-db
POSTGRES_PASSWORD=password-project-db
POSTGRES_PORT=5432
EOF
    log_success ".env.docker создан"
else
    log_info ".env.docker уже существует"
fi

# backend/.env
if [ ! -f "backend/.env" ]; then
    log_info "Создание backend/.env..."
    cat <<EOF > backend/.env
DEBUG=1
SECRET_KEY=django-insecure-dev-key-change-in-production
DJANGO_ALLOWED_HOSTS=localhost 127.0.0.1 [::1]
CORS_ALLOWED_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
DB_ENGINE=django.db.backends.postgresql
POSTGRES_DB=project-db
POSTGRES_USER=user-db
POSTGRES_PASSWORD=password-project-db
DB_HOST=127.0.0.1
DB_PORT=5432
SITE_URL=http://127.0.0.1:3000
EMAIL_HOST_USER=projectdysarthria@gmail.com
EMAIL_HOST_PASSWORD=dummy_password
EMAIL_CONFIRMATION_TOKEN_LIFETIME=15
ADMIN_EMAIL=vadas25@yandex.ru
ADMIN_PASSWORD=admin_password_123
PASSWORD_RESET_TOKEN_LIFETIME=15
EOF
    log_success "backend/.env создан"
else
    log_info "backend/.env уже существует"
fi

# frontend/.env
if [ ! -f "frontend/.env" ]; then
    log_info "Создание frontend/.env..."
    cat <<EOF > frontend/.env
HOST=127.0.0.1
PORT=3000
REACT_APP_API_URL=http://127.0.0.1:8000
EOF
    log_success "frontend/.env создан"
else
    log_info "frontend/.env уже существует"
fi

# ============================================================
# ШАГ 5: Запуск базы данных
# ============================================================
log_info "=== Шаг 5: Запуск базы данных PostgreSQL ==="

# Проверяем, запущен ли уже контейнер
if $DOCKER_CMD compose ps 2>/dev/null | grep -q "postgres.*Up"; then
    log_success "PostgreSQL уже запущен"
else
    log_info "Запуск PostgreSQL..."
    $DOCKER_CMD compose up -d postgres
    log_success "PostgreSQL запущен"
    
    # Ждём инициализации БД
    log_info "Ожидание инициализации базы данных..."
    sleep 5
fi

# ============================================================
# ШАГ 6: Настройка Backend
# ============================================================
log_info "=== Шаг 6: Настройка Backend ==="

# Создание виртуального окружения
if [ ! -d "venv" ]; then
    log_info "Создание виртуального окружения..."
    python3 -m venv venv
    log_success "Виртуальное окружение создано"
else
    log_info "Виртуальное окружение уже существует"
fi

# Активация venv
source venv/bin/activate

# Установка зависимостей backend
if [ -f "backend/requirements.txt" ]; then
    log_info "Установка зависимостей backend..."
    pip install --upgrade pip -q
    pip install -r backend/requirements.txt -q
    log_success "Зависимости backend установлены"
fi

# Создание папки migrations для приложения testing
if [ ! -d "backend/testing/migrations" ]; then
    log_info "Создание папки migrations для приложения testing..."
    mkdir -p backend/testing/migrations
    touch backend/testing/migrations/__init__.py
    log_success "Папка migrations создана"
fi

# Проверка INSTALLED_APPS
if ! grep -q "'testing'" backend/project/settings.py 2>/dev/null; then
    log_warn "Приложение 'testing' не найдено в INSTALLED_APPS. Добавить? (y/n)"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        # Добавляем 'testing' перед закрывающей скобкой INSTALLED_APPS
        sed -i "/^]/i \    'testing'," backend/project/settings.py
        log_success "'testing' добавлен в INSTALLED_APPS"
    fi
fi

# Миграции
log_info "Применение миграций..."
cd backend
python manage.py makemigrations --noinput 2>/dev/null || true
python manage.py migrate --noinput
cd ..
log_success "Миграции применены"

# ============================================================
# ШАГ 7: Настройка Frontend
# ============================================================
log_info "=== Шаг 7: Настройка Frontend ==="

cd frontend

if [ "$USE_YARN" = true ]; then
    if [ ! -d "node_modules" ]; then
        log_info "Установка зависимостей frontend (yarn)..."
        yarn install
        log_success "Зависимости frontend установлены"
    else
        log_info "Зависимости frontend уже установлены"
    fi
else
    if [ ! -d "node_modules" ]; then
        log_info "Установка зависимостей frontend (npm)..."
        npm install
        log_success "Зависимости frontend установлены"
    else
        log_info "Зависимости frontend уже установлены"
    fi
fi

cd ..

# ============================================================
# ШАГ 8: Запуск проекта
# ============================================================
log_info "=== Шаг 8: Запуск проекта ==="

# Остановка предыдущих процессов
pkill -f "manage.py runserver" 2>/dev/null || true
pkill -f "npm start" 2>/dev/null || true

# Запуск backend
log_info "Запуск Backend на порту 8000..."
cd backend
python manage.py runserver 8000 &
BACKEND_PID=$!
cd ..
log_success "Backend запущен (PID: $BACKEND_PID)"

# Запуск frontend
log_info "Запуск Frontend на порту 3000..."
cd frontend
if [ "$USE_YARN" = true ]; then
    yarn start &
else
    npm start &
fi
FRONTEND_PID=$!
cd ..
log_success "Frontend запущен (PID: $FRONTEND_PID)"

# ============================================================
# Итог
# ============================================================
echo ""
echo "============================================================"
log_success "Проект успешно развёрнут!"
echo "============================================================"
echo ""
log_info "Backend:  http://127.0.0.1:8000"
log_info "Frontend: http://127.0.0.1:3000"
echo ""
log_info "PID Backend:  $BACKEND_PID"
log_info "PID Frontend: $FRONTEND_PID"
echo ""
log_info "Для остановки проекта выполните:"
echo "  kill $BACKEND_PID $FRONTEND_PID"
echo "  $DOCKER_CMD compose stop postgres"
echo ""
log_info "Логи Backend:  tail -f backend/logs/ (если настроено)"
log_info "Логи Frontend: выводятся в текущем терминале"
log_info "Логи PostgreSQL: $DOCKER_CMD compose logs postgres"
echo ""
echo "============================================================"
