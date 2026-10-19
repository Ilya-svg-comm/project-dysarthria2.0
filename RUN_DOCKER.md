# Запуск проекта «Дизартрия 2.0» в Docker

Документ описывает **текущее состояние репозитория**, что было сделано для
запуска в Docker, и пошаговую инструкцию для повторного запуска.

---

## 1. Что это за проект

Информационная система для коррекции дизартрии. Состоит из двух частей:

- **backend** — REST API и админка (Django). Предметная область: пользователи
  (кастомная модель `User`, вход по email, подтверждение почты, группы
  `Doctors`/`Administrators`), тесты и упражнения (4 типа: «Пропущенные слова»,
  «Что на изображении», «Пропущенные буквы», «Расположить изображения»),
  результаты прохождения, публичные тесты, капча.
- **frontend** — SPA на React (упражнения, прохождение тестов, профиль, кабинет
  администратора).

---

## 2. Стек

### Backend
| Компонент | Версия / технология |
|---|---|
| Язык | Python 3.10 (образ `python:3.10-slim-bookworm`) |
| Веб-фреймворк | Django 4.2.11 |
| API | Django REST Framework 3.15.1 |
| Аутентификация | SessionAuthentication, `djangorestframework-simplejwt` 5.3.1 |
| БД-драйвер | `psycopg[binary]` 3.x |
| Прочее | django-cors-headers, django-simple-captcha, django-bootstrap-v5 |
| ASGI/WSGI-сервер | gunicorn 21.2.0 (в Docker: `gunicorn project.wsgi --bind 0.0.0.0:8001`) |
| Конфигурация | `python-dotenv` + собственный `backend/config/config.py` |

### Frontend
| Компонент | Версия / технология |
|---|---|
| Рантайм | Node.js 20 (образ `node:20-alpine`) |
| UI | React 18.3.1 (Create React App, `react-scripts` 5.0.1) |
| Роутинг | react-router-dom 6 |
| UI-кит | Chakra UI 2.8, React-Bootstrap 2.10, Bootstrap 5 |
| HTTP | axios 1.7 |
| Данные | react-query 3, @hello-pangea/dnd, react-autosuggest |
| Сборка | `yarn install && yarn build` → статика, отдаётся nginx |

### Инфраструктура
| Компонент | Технология |
|---|---|
| Оркестрация | Docker + Docker Compose (3 сервиса: `postgres`, `django`, `nginx`) |
| БД | PostgreSQL 16 (`postgres:16`) |
| Веб-сервер / reverse proxy | nginx (`nginx:latest`) — раздаёт собранный React, проксирует `/api/`, `/admin/`, `/captcha/`, `/api-auth/`, `/administrator/` на Django (`django:8001`), отдаёт `/static/` и `/media/` из общих volume |

### Схема взаимодействия
```
Браузер → nginx :80 ─┬─ /                → собранный React (SPA)
                     ├─ /api/, /admin/…  → gunicorn → Django :8001
                     ├─ /static/         → shared volume  static_volume
                     └─ /media/          → shared volume  media_volume
Django ────────────────────────────────→ PostgreSQL :5432
```

---

## 3. Что было сделано для запуска (из исходного состояния)

При первом анализе выяснилось:

1. В репозитории **отсутствовали** файлы окружения, на которые ссылается
   `docker-compose.yml` (`env_file: .env.docker`) — без них compose падает.
2. Каталоги миграций `backend/users/migrations` и `backend/testing/migrations`
   **отсутствуют** — они в `.gitignore`, поэтому схему БД нужно создавать на месте.
3. Фронтенд при сборке брал `REACT_APP_BASE_URL=http://127.0.0.1:8000` из
   `frontend/.env` (адрес dev-сервера Django `runserver`). В Docker этот адрес
   неверен: снаружи доступен только nginx на порту 80, поэтому API-запросы из
   браузера ломались.
4. Оставался «висячий» контейнер `postgres` без данных (БД пустая — таблиц нет).

Выполненные действия:

1. **Создан `.env.docker`** (в корне) со всеми переменными, которые читает
   `backend/config/config.py` и `docker-compose.yml`:
   `DEBUG`, `SECRET_KEY`, `DJANGO_ALLOWED_HOSTS`, `CORS_ALLOWED_ORIGINS`,
   `DB_ENGINE`, `POSTGRES_DB/USER/PASSWORD`, `DB_HOST=postgres`, `DB_PORT`,
   `SITE_URL`, `EMAIL_*`, `ADMIN_EMAIL/PASSWORD`, `*_TOKEN_LIFETIME`.
2. **Создан `frontend/.env.production`** с пустым `REACT_APP_BASE_URL=` —
   CRA подхватывает его при `yarn build` (production) и он имеет приоритет над
   `frontend/.env`. Пустое значение = axios шлёт относительные запросы
   (`/api/v0/...`) на тот же origin, а nginx проксирует их в Django.
3. **Удалён старый пустой том Postgres** (`docker compose down -v`) и пересобран
   проект, чтобы БД инициализировалась с учётными данными из `.env.docker`.
4. **Собраны образы**: `docker compose build` (Django + nginx/React).
5. **Запущены сервисы**: `docker compose up -d` (postgres → django → nginx).
6. **Созданы и применены миграции**:
   `makemigrations users testing` → `migrate`.
7. **Инициализация данных**: `python entrypoint.py` — создаёт группы
   `Doctors`/`Administrator`, суперпользователя и 4 типа упражнений.
8. **Собран статик Django**: `collectstatic --noinput` (161 файл — стили админки).
9. **Проверена работоспособность** через `curl` (см. раздел 5).

### Инструменты, которыми это делалось
- **Docker 29.9 / Docker Compose v5.6** — сборка и запуск.
- **shell (bash)** — команды `docker compose`, `curl`, `psql` внутри контейнера.
- **pg_admin через `psql`** — проверка, что БД пустая (безопасно пересоздавать том).
- Нативные инструменты в образах: `python:3.10`, `manage.py`, `gunicorn`,
  `node:20` + `yarn`, `postgres:16`, `nginx`.

---

## 4. Инструкция по запуску

### 4.1. Требования
- Docker Engine и Docker Compose (проверено на Docker 29.9 / Compose 5.6).
- Свободные порты: **80** (nginx), **8001** (Django/gunicorn), **5432** (Postgres).

### 4.2. Первый запуск

```bash
# 1. Перейти в корень проекта
cd /root/project-dysarthria2.0

# 2. Убедиться, что есть .env.docker (уже создан; при отсутствии — создать, см. раздел 6)
ls -la .env.docker

# 3. Собрать образы (первый раз долго: pip install + yarn install + yarn build)
docker compose build

# 4. Поднять сервисы
docker compose up -d

# 5. Создать и применить миграции
docker compose exec django python manage.py makemigrations users testing
docker compose exec django python manage.py migrate

# 6. Инициализация: группы, суперпользователь, типы упражнений
docker compose exec django python entrypoint.py

# 7. Собрать статику Django (для админки через nginx)
docker compose exec django python manage.py collectstatic --noinput
```

### 4.3. Адреса после запуска
| Что | URL |
|---|---|
| Frontend (SPA) | http://localhost/ |
| Django Admin | http://localhost/admin/ |
| REST API | http://localhost/api/v0/ |
| Прямой доступ к Django | http://localhost:8001/ |

### 4.4. Учётные данные суперпользователя (из `.env.docker`)
- email: **vadas25@yandex.ru**
- пароль: **password**

### 4.5. Повторный запуск (после остановки)

```bash
cd /root/project-dysarthria2.0
docker compose up -d
```
Миграции/`entrypoint.py`/`collectstatic` повторно выполнять не нужно — данные
хранятся в Docker-томе `project-dysarthria20_data`, статика — в `static_volume`.

### 4.6. Полезные команды
```bash
docker compose ps                 # статус контейнеров
docker compose logs -f django     # логи backend
docker compose logs -f nginx      # логи nginx
docker compose stop               # остановить (данные сохраняются)
docker compose down               # удалить контейнеры и сеть (данные сохраняются)
docker compose down -v            # удалить контейнеры + тома (ПОЛНЫЙ сброс БД/статики)
docker compose exec django python manage.py createsuperuser   # ещё один админ
docker compose exec postgres psql -U user-db -d project-db    # открыть psql
```

> Примечание: в `Makefile` уже есть цель `make build`, которая делает
> `up -d --build` + `makemigrations` + `migrate` + `entrypoint`. Она **не** делает
> `collectstatic`, поэтому статика админки без ручного шага 7 не появится.

---

## 5. Проверка работоспособности (выполнено)

```
GET /                       → 200, text/html            (React SPA)
GET /static/js/main.*.js    → 200, application/javascript
GET /api/v0/tests/          → 200, []
GET /api/v0/exercise-types/ → 200, [{"id":1,"name":"Пропущенные слова"}, …4 шт.]
GET /admin/login/           → 200, text/html            (страница входа админки)
```
Логи `django` и `nginx` — без ошибок. В собранном JS-бандле нет `127.0.0.1:8000`
(запросы идут относительными путями через nginx).

---

## 6. Содержимое `.env.docker` (справочно)

```dotenv
DEBUG=1
SECRET_KEY=dev-only-secret-key-change-me-in-production-0123456789abcdef
DJANGO_ALLOWED_HOSTS=localhost 127.0.0.1 [::1]
CORS_ALLOWED_ORIGINS=http://localhost http://127.0.0.1
DB_ENGINE=django.db.backends.postgresql
POSTGRES_DB=project-db
POSTGRES_USER=user-db
POSTGRES_PASSWORD=password-project-db
DB_HOST=postgres
DB_PORT=5432
SITE_URL=http://localhost
EMAIL_HOST_USER=projectdysarthria@gmail.com
EMAIL_HOST_PASSWORD=password
EMAIL_CONFIRMATION_TOKEN_LIFETIME=15
ADMIN_EMAIL=vadas25@yandex.ru
ADMIN_PASSWORD=password
PASSWORD_RESET_TOKEN_LIFETIME=15
```

> Для production обязательно сменить `SECRET_KEY`, пароли БД/админа, отключить
> `DEBUG`, а для `SITE_URL`/`CORS` указать реальный домен.

---

## 7. Изменённые/созданные файлы

| Файл | Действие | Назначение |
|---|---|---|
| `.env.docker` | создан | переменные окружения для compose (backend + postgres) |
| `frontend/.env.production` | создан | пустой `REACT_APP_BASE_URL` → API через nginx |
| `backend/users/migrations/0001_initial.py` | создан (в контейнере, `.gitignore`) | схема приложения users |
| `backend/testing/migrations/0001_initial.py`, `0002_initial.py` | создан (`.gitignore`) | схема приложения testing |

Исходный код приложения **не изменялся** — только добавлены конфигурационные
файлы окружения.
