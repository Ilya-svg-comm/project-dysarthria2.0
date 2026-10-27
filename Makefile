# Единый Makefile для запуска проекта
.PHONY: build build-run migrate collectstatic run-entrypoint run stop down logs ps check-env

# Проверка наличия корневого .env.docker
check-env:
	@test -f .env.docker || (echo "Ошибка: файл .env.docker не найден. Скопируйте .env.docker.form в .env.docker и заполните значения."; exit 1)

# Сборка образов
build: check-env
	docker compose build

# Сборка, миграции, инициализация, статика и запуск (build-run)
build-run: build migrate run-entrypoint collectstatic run
	@echo "Проект запущен. Фронт: http://localhost, API: http://localhost/api/v0/"

# Применение миграций
migrate: check-env
	docker compose up -d postgres
	@echo "Ожидание готовности postgres..."
	@until docker compose exec -T postgres pg_isready -U $$(grep -E '^POSTGRES_USER=' .env.docker | cut -d '=' -f2-) -d $$(grep -E '^POSTGRES_DB=' .env.docker | cut -d '=' -f2-) 2>/dev/null; do sleep 2; done
	docker compose up -d backend
	docker compose exec -T backend python manage.py makemigrations users testing
	docker compose exec -T backend python manage.py migrate

# Сбор статики Django (нужна для админки, отдаётся через nginx)
collectstatic:
	docker compose exec -T backend python manage.py collectstatic --noinput

# Создание суперпользователя, групп, типов упражнений
run-entrypoint:
	docker compose exec -T backend python entrypoint.py

# Запуск всех контейнеров
run: check-env
	docker compose up -d postgres backend frontend

# Остановка
stop:
	docker compose stop

# Полная остановка с удалением контейнеров/сетей
down:
	docker compose down

# Логи
logs:
	docker compose logs -f

# Статус
ps:
	docker compose ps
