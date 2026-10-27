# Project dysarthria

Информационная система для коррекции дизартрии.

> Актуальная инструкция по запуску и настройке — в этом README.

## Стек

### Backend

| Компонент | Версия / технология |
|---|---|
| Язык | Python 3.10 (образ `python:3.10-slim-bookworm`) |
| Веб-фреймворк | Django 4.2.11 |
| API | Django REST Framework 3.15.1 |
| Аутентификация | `SessionAuthentication`; `djangorestframework-simplejwt` установлен, но JWT-аутентификация в `settings.py` отключена |
| Драйвер БД | `psycopg[binary]` 3.x |
| Дополнительно | django-cors-headers, django-simple-captcha, django-bootstrap-v5, Pillow |
| WSGI-сервер | gunicorn 21.2.0, команда `gunicorn project.wsgi:application --bind 0.0.0.0:8001` |
| Конфигурация | `python-dotenv` + `backend/config/config.py` |

### Frontend

| Компонент | Версия / технология |
|---|---|
| Рантайм | Node.js 20 (образ `node:20-alpine` для сборки) |
| UI | React 18.3.1, Create React App (`react-scripts` 5.0.1) |
| Роутинг | react-router-dom 6 |
| UI-библиотеки | Chakra UI 2.8, React-Bootstrap 2.10, Bootstrap 5 |
| HTTP и состояние | axios 1.7, react-query 3 |
| Drag-and-drop | `@hello-pangea/dnd` 18 |
| Сборка | `yarn install && yarn build`, пакетный менеджер yarn 1.22.22 |
| Раздача статики | nginx из multi-stage-сборки (`nginx:latest`) |

### Инфраструктура

| Компонент | Технология |
|---|---|
| Оркестрация | Docker Compose, три сервиса: `postgres`, `backend`, `frontend` |
| БД | PostgreSQL 16 (`postgres:16`), named volume `data` |
| Backend | gunicorn на порту `8001`; код подключён bind-mount, статика и media — в отдельных volume |
| Frontend | multi-stage-сборка Node.js → nginx, опубликован на порту `80` |
| Reverse proxy | nginx раздаёт React и проксирует `/api/`, `/admin/`, `/captcha/`, `/api-auth/`, `/administrator/` в `backend:8001` |
| Файлы | `/static/` и `/media/` отдаются nginx из общих volume `static_volume` и `media_volume` |
| Объектное хранилище | MinIO пока не запускается; интеграция отложена до следующих обновлений |

### Схема взаимодействия

```text
Браузер → frontend/nginx :80
  ├─ /                 → собранный React (SPA)
  ├─ /api/             → backend:8001 (Django/gunicorn)
  ├─ /admin/           → backend:8001
  ├─ /captcha/         → backend:8001
  ├─ /api-auth/        → backend:8001
  ├─ /administrator/   → backend:8001
  ├─ /static/          → static_volume (статика Django; /static/js, /static/css и /static/media — из React-сборки)
  └─ /media/           → media_volume

backend → postgres:5432
```

Порты на хосте: `80` — frontend, `8001` — backend, `5432` — PostgreSQL.

## Быстрый запуск через Docker

Требуются Docker Engine и Docker Compose v2. Все команды выполняются из корня
проекта, где находится `Makefile`.

```bash
cp .env.docker.form .env.docker
# Заполните SECRET_KEY, POSTGRES_PASSWORD, ADMIN_PASSWORD,
# EMAIL_HOST_PASSWORD и остальные значения.

make check-env   # проверить наличие .env.docker
make build-run   # собрать, применить миграции, создать данные, собрать статику и запустить
make ps          # проверить статус контейнеров
```

`make build-run` выполняет цепочку `build → migrate → run-entrypoint →
collectstatic → run`. Для повторного запуска после `make stop` достаточно
`make run`.

## Адреса после запуска

| Что | URL | Ожидаемый ответ |
|---|---|---|
| Frontend (SPA) | http://localhost/ | `200`, HTML |
| Корень REST API | http://localhost/api/v0/ | `200`, JSON со списком endpoint'ов |
| Пример API | http://localhost/api/v0/exercise-types/ | `200`, JSON с типами упражнений |
| Django Admin | http://localhost/admin/ | без авторизации — `302` на `/admin/login/`; страница входа — `200` |
| Backend напрямую | http://localhost:8001/ | `404`, так как у Django нет маршрута `/`; используется только для диагностики |

Проверка после запуска:

```bash
curl -I http://localhost/
curl -fsS http://localhost/api/v0/exercise-types/
curl -I http://localhost/admin/login/
docker compose ps
```

Если API отвечает `502`, backend ещё не готов или упал — смотрите
`docker compose logs backend`.

MinIO в текущей конфигурации не запускается: сервис будет добавлен в следующих
обновлениях.

## Суперпользователь

Суперпользователь создаётся командой `make run-entrypoint` (или
`docker compose exec -T backend python entrypoint.py`) из переменных
`ADMIN_EMAIL` и `ADMIN_PASSWORD` в `.env.docker`.

- В шаблоне `.env.docker.form` по умолчанию указаны
  `ADMIN_EMAIL=vadas25@yandex.ru` и `ADMIN_PASSWORD=change-me`. Замените пароль
  до первого запуска.
- `entrypoint.py` создаёт пользователя только если пользователя с таким email
  ещё нет. Повторный запуск безопасен.
- Если суперпользователь уже создан, изменение `ADMIN_PASSWORD` в
  `.env.docker` не изменит его пароль. Смените пароль через Django Admin или
  командой:

```bash
docker compose exec -T backend python manage.py changepassword <email>
```

`<email>` — значение `ADMIN_EMAIL` из `.env.docker`.

## Команды Makefile

| Команда | Что делает | Когда использовать |
|---|---|---|
| `make check-env` | Проверяет, что в корне есть `.env.docker`. Если файла нет, выводит ошибку и завершает выполнение. | Перед первым запуском или для диагностики. Также вызывается из `build`, `migrate` и `run`. |
| `make build` | Собирает Docker-образы backend и frontend (`docker compose build`). Контейнеры не запускает. | После изменения `Dockerfile`, зависимостей или frontend-кода. |
| `make migrate` | Поднимает `postgres`, ждёт готовности Postgres, поднимает `backend`, выполняет `makemigrations users testing` и `migrate`. Frontend не запускает. | Для создания/обновления схемы БД. Файлы миграций создаются в контейнере (владелец `root`) и не коммитятся. |
| `make collectstatic` | Выполняет `collectstatic --noinput` в контейнере `backend`. Собирает статику Django для админки в общий volume. | После `make migrate` или после изменения статики. Требует запущенного backend. |
| `make run-entrypoint` | Запускает `entrypoint.py`: создаёт группы `Doctors`/`Administrators`, суперпользователя и типы упражнений. | После `make migrate`, если нужно инициализировать данные. |
| `make run` | Запускает `postgres`, `backend`, `frontend` через `docker compose up -d`. Не собирает образы, не применяет миграции и не выполняет инициализацию. | Для повторного запуска уже подготовленного проекта. |
| `make build-run` | Полный первый запуск: `build → migrate → run-entrypoint → collectstatic → run`. | Для первого запуска или после существенных изменений. Не запускайте с `make -j`: порядок шагов важен. |
| `make stop` | Останавливает контейнеры (`docker compose stop`). Контейнеры и данные сохраняются. | Для паузы без удаления данных. |
| `make down` | Удаляет контейнеры и сеть (`docker compose down`). Named volumes с БД, статикой и media сохраняются. | Когда нужно пересоздать контейнеры, но сохранить данные. |
| `make logs` | Показывает и отслеживает логи всех сервисов (`docker compose logs -f`). | Для диагностики. Выход — `Ctrl+C`. |
| `make ps` | Показывает статус контейнеров (`docker compose ps`). | Для проверки, что сервисы запущены. |

Файлы миграций не отслеживаются git (`.gitignore`) и создаются заново на
чистом клоне. В контейнере они принадлежат `root`.

Полный сброс с удалением томов (БД, статика, media):

```bash
docker compose down -v
make build-run
```

> Старый том `project-dysarthria20_minio_data` от предыдущей конфигурации не
> входит в текущий compose и командой `docker compose down -v` не удаляется.
> Он не используется; при необходимости удалите его вручную.

## Полезные команды Docker

| Задача | Команда |
|---|---|
| Статус контейнеров | `make ps` или `docker compose ps` |
| Логи всех сервисов | `make logs` |
| Логи backend | `docker compose logs -f backend` |
| Логи frontend | `docker compose logs -f frontend` |
| Последние 200 строк логов backend | `docker compose logs --tail=200 backend` |
| Запустить подготовленный проект | `make run` |
| Остановить без удаления контейнеров | `make stop` |
| Удалить контейнеры и сеть, сохранив данные | `make down` |
| Перезапустить backend после изменения кода | `docker compose restart backend` |
| Пересобрать frontend после изменения кода или nginx | `docker compose build frontend && make run` |
| Применить миграции | `make migrate` |
| Повторно выполнить инициализацию | `make run-entrypoint` |
| Пересобрать статику Django | `make collectstatic` |
| Открыть Django shell | `docker compose exec -T backend python manage.py shell` |
| Создать ещё одного суперпользователя | `docker compose exec -T backend python manage.py createsuperuser` |
| Сменить пароль пользователя | `docker compose exec -T backend python manage.py changepassword <email>` |
| Открыть psql | `docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'` |
| Запустить тесты backend | `docker compose exec -T backend python manage.py test --parallel` |
| Полный сброс с удалением данных | `docker compose down -v && make build-run` |

Примечания:

- Команды `docker compose exec` требуют запущенного контейнера. `make migrate`
  сам поднимает `postgres` и `backend`; для `collectstatic` и `run-entrypoint`
  backend также должен быть запущен.
- Backend работает под gunicorn без автоперезагрузки: после изменения Python-кода
  выполните `docker compose restart backend`.
- Изменения frontend, `frontend/nginx.conf` или `frontend/Dockerfile` требуют
  пересборки frontend.
- `make down` сохраняет named volumes. Команда `docker compose down -v`
  удаляет БД, статику и media без возможности восстановления.
- Порт `8001` опубликован наружу. В production backend лучше не публиковать,
  оставив доступ только через nginx.

## Локальная разработка backend

```bash
python -m venv venv
source venv/bin/activate
pip install -r backend/requirements.txt

cp .env.docker.form .env.docker   # нужен для Postgres из compose
cp backend/.env.form backend/.env

docker compose up -d postgres
cd backend
python manage.py makemigrations users testing
python manage.py migrate
python manage.py runserver 8000
```

`backend/.env` используется локальным `runserver` и читается через
`backend/config/config.py`. В Docker backend получает переменные из
`.env.docker`, а не из `backend/.env`.

Миграции создаются локально и не отслеживаются git. Для остановки Postgres:
`docker compose stop postgres`.

## Локальная разработка frontend

```bash
cd frontend
cp .env.form .env   # локальный env, не отслеживается git
yarn install
yarn start
```

Frontend dev-сервер будет доступен на `http://127.0.0.1:3000`, backend — на
`http://127.0.0.1:8000`. В Docker production-сборка использует
`frontend/.env.production`, а не `frontend/.env`.

## Тесты backend

В текущем `Makefile` нет целей `test-backend-*`. Запускайте тесты через
Docker-контейнер:

```bash
docker compose exec -T backend python manage.py test --parallel
docker compose exec -T backend python manage.py test users --parallel
docker compose exec -T backend python manage.py test user_api --parallel
docker compose exec -T backend python manage.py test api_v0 --parallel
```

Перед тестами должны быть применены миграции и запущен backend: выполните
`make build-run` для первого запуска или `make migrate`, затем `make run`.

Если `--parallel` падает из-за нехватки соединений с БД, уберите этот флаг.

## Окружение

В проекте используются четыре env-файла.

| Файл | Шаблон | Назначение |
|---|---|---|
| `.env.docker` | `.env.docker.form` | Docker Compose: переменные для `postgres` и `backend` |
| `backend/.env` | `backend/.env.form` | локальный запуск backend через `runserver` |
| `frontend/.env` | `frontend/.env.form` | локальная разработка frontend через `yarn start` |
| `frontend/.env.production` | `frontend/.env.production.form` | production-сборка frontend в Docker (`yarn build`) |

Корневой `.env` в текущей схеме не используется: compose читает
`.env.docker`, а backend при локальном запуске — `backend/.env`.

Создание локальных файлов из шаблонов:

```bash
cp .env.docker.form .env.docker
cp backend/.env.form backend/.env
cp frontend/.env.form frontend/.env
```

Для Docker-запуска обязателен только `.env.docker`. Остальные два файла нужны
для локальной разработки. Если файл уже существует, не перезаписывайте его без
необходимости.

### `.env.docker`

Основной файл для Docker Compose. Он передаётся сервисам `postgres` и
`backend` через `env_file` и содержит:

- настройки Django: `DEBUG`, `SECRET_KEY`, `DJANGO_ALLOWED_HOSTS`,
  `CORS_ALLOWED_ORIGINS`, `SITE_URL`;
- настройки БД: `DB_ENGINE`, `POSTGRES_DB`, `POSTGRES_USER`,
  `POSTGRES_PASSWORD`, `DB_HOST`, `DB_PORT`;
- настройки почты и времени жизни токенов: `EMAIL_HOST_USER`,
  `EMAIL_HOST_PASSWORD`, `EMAIL_CONFIRMATION_TOKEN_LIFETIME`,
  `PASSWORD_RESET_TOKEN_LIFETIME`;
- данные первоначального администратора: `ADMIN_EMAIL`, `ADMIN_PASSWORD`.

Полный список и значения-заглушки находятся в `.env.docker.form`.

`POSTGRES_DB`, `POSTGRES_USER` и `POSTGRES_PASSWORD` применяются при **первой**
инициализации тома PostgreSQL. Если изменить их после создания тома, backend
не сможет подключиться к БД; потребуется пересоздать том
(`docker compose down -v`) либо отдельно изменить пользователя/пароль в
PostgreSQL.

`ADMIN_EMAIL` и `ADMIN_PASSWORD` используются только при создании
суперпользователя через `entrypoint.py`. Изменение этих переменных после
создания пользователя не меняет существующую учётную запись.

### `backend/.env`

Файл для локального запуска backend без Docker. `backend/config/config.py`
загружает его через `python-dotenv`, если файл существует. В нём задаются те же
группы переменных, что и в `.env.docker`, но с локальными адресами:
`DB_HOST=localhost` и `SITE_URL`/CORS для frontend на порту `3000`.

Для Docker-контейнера этот файл не нужен: compose передаёт переменные из
`.env.docker`. Шаблон — `backend/.env.form`.

### `frontend/.env`

Файл для локальной разработки (`yarn start`). Содержит `HOST`, `PORT` и
`REACT_APP_BASE_URL`. В шаблоне `frontend/.env.form` указан локальный backend
`http://127.0.0.1:8000`.

В Docker-сборке используется не он, а `frontend/.env.production`.

### `frontend/.env.production`

Файл для production-сборки frontend в Docker (`yarn build`). Используйте
шаблон `frontend/.env.production.form` для копирования.

```bash
cp frontend/.env.production.form frontend/.env.production
```

При `yarn build` задаёт пустой `REACT_APP_BASE_URL=`;
тогда axios отправляет относительные запросы (`/api/v0/...`) на тот же origin,
а nginx проксирует их в backend.

Не указывайте здесь `http://127.0.0.1:8000`: в Docker это сломает API.
Локальный адрес нужен только в `frontend/.env` для `yarn start`.

Основной axios-клиент использует относительные пути. При этом в
`frontend/src/Pages/Components/AssignDoctorGroups.js` пока остаются абсолютные
адреса `http://127.0.0.1:8000`, поэтому назначение врача при открытии сайта не
с localhost может не работать.

### Шаблоны env

Шаблоны `.env.docker.form`, `backend/.env.form`, `frontend/.env.form` и
`frontend/.env.production.form` содержат только заглушки (`change-me`,
локальные адреса).

### Текущее ограничение настроек

В `backend/project/settings.py` сейчас `DEBUG = True`, `ALLOWED_HOSTS = ['*']`,
а CORS разрешён для всех источников. Поэтому переменные `DEBUG`,
`DJANGO_ALLOWED_HOSTS` и `CORS_ALLOWED_ORIGINS` из env фактически не
ограничивают доступ. Перед production эти настройки нужно привести в порядок в
коде.
