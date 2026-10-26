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
   **отсутствуют в репозитории** — они в `.gitignore`, поэтому схему БД нужно
   создавать на месте.
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

---

## 8. Запуск через Makefile (актуальная конфигурация)

> Разделы 1–7 описывают предыдущий вариант `docker-compose.yml` (`django` + `nginx`).
> В текущей рабочей копии:
>
> - backend-сервис называется **`backend`** (не `django`);
> - frontend собирается в отдельный nginx-контейнер **`frontend`**;
> - добавлен сервис **`minio`**;
> - `docker-compose.yml` и `Makefile` читают корневой **`.env.docker`**
>   (шаблон — `.env.docker.form`).
>
> Команды из разделов 4.2 и 4.6, где используется `docker compose exec django ...`,
> для текущего compose-файла не подходят — используйте `backend` или цели Makefile.

### 8.1. Цели Makefile

| Цель | Что делает | Важно |
|---|---|---|
| `make build` | `docker compose build` — собирает образы backend и frontend | не запускает контейнеры |
| `make migrate` | поднимает `postgres` и `minio`, ждёт готовности Postgres, поднимает `backend`, выполняет `makemigrations users testing` и `migrate` | нужен `.env.docker`; образы должны быть собраны; frontend не запускается; файлы миграций создаются в контейнере и не коммитятся (`.gitignore`) |
| `make collectstatic` | `python manage.py collectstatic --noinput` в `backend` | нужен запущенный backend; статика админки появляется в общем volume |
| `make run-entrypoint` | `python entrypoint.py` в `backend` — группы, суперпользователь, типы упражнений | выполнять после `make migrate` |
| `make run` | запускает `postgres`, `minio`, `backend`, `frontend` | не делает миграции и инициализацию |
| `make build-run` | `build` → `migrate` → `run-entrypoint` → `collectstatic` → `run` | полный первый запуск одной командой |
| `make stop` | останавливает контейнеры | контейнеры и данные сохраняются |
| `make down` | удаляет контейнеры и сеть | named volumes с БД/статикой сохраняются |
| `make logs` | `docker compose logs -f` по всем сервисам | выход — `Ctrl+C` |
| `make ps` | статус контейнеров | |

`make build-run` выполняет шаги последовательно. Не запускайте его с `make -j`:
порядок «сборка → миграции → инициализация → статика → запуск» важен.

### 8.2. Что должно быть готово

1. **Docker Engine и Compose v2.** Проверка:

   ```bash
   docker compose version
   docker info
   ```

   Если `docker info` пишет `Cannot connect to the Docker daemon` или
   `/var/run/docker.sock: no such file`, демон не запущен:

   ```bash
   sudo systemctl start docker
   # если пользователь ещё не в группе docker:
   sudo usermod -aG docker "$USER"
   # после этого нужно перелогиниться
   ```

   Если группа уже добавлена, но текущая сессия её ещё не видит, можно не
   перелогиниваться, а выполнить команды в новом shell с этой группой:

   ```bash
   newgrp docker -c 'docker info'
   newgrp docker -c 'make build-run'
   ```

2. **Свободные порты:** `80` (frontend/nginx), `8001` (backend), `5432` (Postgres),
   `9000` и `9001` (MinIO). Проверка:

   ```bash
   ss -ltnp | grep -E ':(80|5432|8001|9000|9001)\b'
   ```

   Если порт занят, остановите host-сервис (например, системный nginx/Postgres)
   или измените публикацию портов в `docker-compose.yml`, например `"8080:80"`
   и `"5433:5432"`. Внутри compose backend всё равно подключается к `postgres:5432`
   по имени сервиса — менять `DB_HOST`/`DB_PORT` в `.env.docker` при смене только
   внешнего порта не нужно.

3. **Корневой `.env.docker`.** Скопируйте шаблон и заполните секреты:

   ```bash
   cp .env.docker.form .env.docker
   # отредактируйте SECRET_KEY, POSTGRES_PASSWORD, ADMIN_PASSWORD,
   # EMAIL_HOST_PASSWORD и остальные значения
   test -f .env.docker && echo ".env.docker найден"
   ```

   Текущий compose читает именно `.env.docker` (через `env_file`), корневой
   `.env` для запуска не нужен. Дополнительный флаг `--env-file` тоже не
   требуется: значения передаются в контейнеры напрямую из `env_file`.
   `.env.docker` уже добавлен в `.gitignore` — реальные пароли не должны
   попадать в git.
   Если оставить значения `change-me`, контейнеры запустятся, но это небезопасно;
   для повторяемого тестового запуска значения должны совпадать во всех сервисах.

   Важно: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` применяются при
   **первой** инициализации тома Postgres. Если изменить их после создания тома,
   будет ошибка аутентификации — поможет только полный сброс томов (см. 8.6).

4. **Имя backend-сервиса в nginx.** В `frontend/nginx.conf` upstream должен
   указывать на `backend`:

   ```bash
   grep -n 'server .*:8001' frontend/nginx.conf
   # ожидается: server backend:8001;
   ```

   В репозитории это уже исправлено. Если у вас старая копия и nginx падает с
   `host not found in upstream "django:8001"`, замените `django` на `backend`
   и пересоберите frontend:

   ```bash
   sed -i 's/server django:8001;/server backend:8001;/' frontend/nginx.conf
   docker compose build frontend
   ```

5. **Адрес API для production-сборки frontend.** В `frontend/.env.production`
   должно быть пустое значение:

   ```dotenv
   REACT_APP_BASE_URL=
   ```

   Тогда axios отправляет относительные запросы (`/api/v0/...`), а nginx
   проксирует их в backend. Не указывайте здесь `http://127.0.0.1:8000` —
   в Docker-сборке это сломает API. Адрес `http://127.0.0.1:8000` нужен только
   для локальной разработки (`yarn start` + `frontend/.env`).

   Для локальной разработки скопируйте шаблоны (реальные файлы в `.gitignore`):

   ```bash
   cp backend/.env.form backend/.env
   cp frontend/.env.form frontend/.env
   ```

### 8.3. Первый запуск

Полный запуск одной командой:

```bash
make build-run
make ps
```

`make build-run` теперь также запускает frontend и собирает статику Django.
Пошаговый вариант (если нужно видеть каждый этап отдельно):

```bash
make build          # собрать образы
make migrate        # поднять БД и backend, создать и применить миграции
make run-entrypoint # группы, суперпользователь, типы упражнений
make collectstatic  # стили админки
make run            # запустить frontend и остальные сервисы
```

После запуска:

| Что | URL |
|---|---|
| Frontend (SPA) | http://localhost/ |
| REST API | http://localhost/api/v0/ |
| Django Admin | http://localhost/admin/ |
| Backend напрямую (gunicorn) | http://localhost:8001/ |
| MinIO Console | http://localhost:9001/ |

Логин в админку — `ADMIN_EMAIL` / `ADMIN_PASSWORD` из `.env.docker`.

Проверка:

```bash
curl -I http://localhost/
curl -fsS http://localhost/api/v0/exercise-types/
curl -I http://localhost/admin/login/
docker compose ps
```

Ожидается `200` для frontend и админки, JSON с четырьмя типами упражнений для API.
Если API отвечает `502`, backend ещё не готов или упал — смотрите
`docker compose logs backend`.

### 8.4. Повторный запуск и изменения кода

После `make stop` или `make down` (без `-v`) достаточно:

```bash
make run
```

Повторно выполнять `migrate`, `run-entrypoint` и `collectstatic` не нужно:
данные и статика хранятся в named volumes.

- Изменения backend подхватываются через bind-mount `./backend`, но gunicorn
  **не** перезагружает код автоматически:

  ```bash
  docker compose restart backend
  ```

- Изменения frontend, `frontend/nginx.conf` или Dockerfile требуют пересборки:

  ```bash
  make build
  make run
  ```

- Если изменилась только статика Django:

  ```bash
  make collectstatic
  ```

### 8.5. Типовые ошибки

| Симптом | Причина | Решение |
|---|---|---|
| `Cannot connect to the Docker daemon` / `docker.sock: no such file` | демон Docker не запущен или нет прав | запустить Docker, добавить пользователя в группу `docker`, перелогиниться |
| `env file .../.env.docker not found` | не создан корневой `.env.docker` | `cp .env.docker.form .env.docker` |
| `pull access denied for minio/minio` | официальный образ `minio/minio` больше недоступен на Docker Hub | в текущем compose используется `elestio/minio:latest`; не заменяйте его на старый `minio/minio:latest` |
| Postgres не стартует, в логах пустые/неверные `POSTGRES_*` | `.env.docker` пустой или содержит неверные значения | заполнить `.env.docker`; проверить, что compose запускается из корня проекта |
| `Bind for 0.0.0.0:80 failed: port is already allocated` (или `5432`) | порт занят host-сервисом/другим контейнером | остановить занявший сервис или изменить порт в `docker-compose.yml` |
| `host not found in upstream "django:8001"` | старый `frontend/nginx.conf` | заменить на `backend:8001` и пересобрать frontend |
| `make migrate` завис на «Ожидание готовности postgres…» | Postgres не стартует, неверные креды или старый том | `Ctrl+C`, `docker compose logs postgres`, при необходимости `docker compose down -v` |
| `password authentication failed for user "user-db"` | том Postgres создан со старыми `POSTGRES_*` | полный сброс: `docker compose down -v`, затем `make build-run` |
| `/admin/` открывается без стилей | не выполнена `collectstatic` | `make collectstatic` |
| `Conflict. The container name "/postgres" is already in use` | фиксированные `container_name` конфликтуют с другим проектом | остановить/удалить старый контейнер или изменить имена в compose |
| `make test-backend-*: No rule to make target` | README описывает старый Makefile, тестовых целей сейчас нет | запускать тесты вручную (см. 8.7) |

`make logs` специально работает в режиме `-f` и не завершается. Для разового
просмотра используйте:

```bash
docker compose logs --tail=200 backend
docker compose logs --tail=200 frontend
```

### 8.6. Полный сброс

Удаляет контейнеры, сеть и **все** named volumes (`data`, `static_volume`,
`media_volume`, `minio_data`) — БД, загруженные файлы и статика будут потеряны:

```bash
docker compose down -v
make build-run
```

Если нужно пересобрать образы без кэша:

```bash
docker compose build --no-cache
make build-run
```

### 8.7. Тесты backend

В текущем Makefile целей `test-backend-*` больше нет, хотя README на них
ссылается. Тесты запускаются внутри backend-контейнера:

```bash
# все приложения
docker compose exec -T backend python manage.py test --parallel

# или выборочно
docker compose exec -T backend python manage.py test users user_api api_v0 --parallel
```

Перед тестами должны быть подняты Postgres и применены миграции. Если
`--parallel` падает из-за нехватки соединений с БД, уберите этот флаг.

### 8.8. Результаты проверки в текущем окружении

Проверка выполнена 2026-10-26 на реальном Docker daemon (Docker 29.9.2,
Compose 5.6.1). Пользователь был добавлен в группу `docker`, но текущая
сессия ещё не видела эту группу, поэтому команды запускались через
`newgrp docker -c '...'`.

Проверенные команды и результат:

| Команда | Результат |
|---|---|
| `docker compose config` | OK, ошибок и предупреждений нет |
| `make check-env` | OK при наличии `.env.docker`; без файла — понятная ошибка |
| `make build` | OK; backend и frontend собраны (предупреждения ESLint не фатальны) |
| `make migrate` | OK; Postgres дождался готовности, миграции применены |
| `make run-entrypoint` | OK; созданы группы, суперпользователь и 4 типа упражнений |
| `make collectstatic` | OK; скопирован 161 файл статики |
| `make run` | OK; запущены postgres, minio, backend, frontend |
| `make ps` | OK; все контейнеры Up, Postgres healthy |
| `make logs` | OK; работает в режиме `-f`, останавливается `Ctrl+C` |
| `make stop` | OK; контейнеры остановлены, `make ps` после этого пуст |
| `make run` после `stop` | OK; контейнеры снова запущены |
| `make down` | OK; контейнеры и сеть удалены, named volumes сохранены |

Полный чистый запуск также проверен:

```bash
docker compose down -v
make build-run
```

Команда завершилась успешно: образы собраны, миграции применены, созданы
суперпользователь и типы упражнений, статика собрана, все сервисы запущены.

Проверка HTTP после `make build-run`:

| URL | Ответ |
|---|---|
| `http://localhost/` | `200 text/html` |
| `http://localhost/api/v0/exercise-types/` | `200`, JSON с 4 типами упражнений |
| `http://localhost/admin/login/` | `200 text/html` |
| `http://localhost/static/admin/css/base.css` | `200 text/css` |
| `http://localhost:8001/` | `404` (ожидаемо: у Django нет маршрута `/`) |
| `http://localhost:9000/minio/health/live` | `200` |

#### MinIO: замена официального образа

При проверке `minio/minio:latest` не скачался:

```text
pull access denied for minio/minio, repository does not exist or may require 'docker login'
```

Официального образа `minio/minio` на Docker Hub сейчас нет, поэтому в
`docker-compose.yml` используется совместимый образ:

```yaml
image: elestio/minio:latest
```

Он успешно запускается, отвечает на `http://localhost:9000/minio/health/live`
кодом `200`, а healthcheck compose переходит в `healthy` (иногда через
~30 секунд после старта). Если в вашем окружении доступен другой проверенный
образ MinIO, его можно указать вместо `elestio/minio:latest`, сохранив
`command: server /data --console-address ":9001"`.

### 8.9. Известные ограничения

- Официальный образ `minio/minio` сейчас недоступен на Docker Hub. В compose
  используется `elestio/minio:latest`; для production проверьте источник и
  зафиксируйте образ по digest. Сервис MinIO пока не используется backend-кодом,
  но нужен для `make migrate`/`make run` в текущей конфигурации.
- `make migrate` создаёт файлы миграций через bind-mount, поэтому на хосте они
  принадлежат `root`. Это ожидаемо: контейнер запускается от root, а каталоги
  миграций находятся в `.gitignore` и не коммитятся. На чистом клоне они
  создаются заново.
- Цикл ожидания Postgres в `make migrate` не имеет таймаута: при неверных
  данных/сломанном контейнере он будет ждать бесконечно — прерывайте `Ctrl+C`.
- В `frontend/src/Pages/Components/AssignDoctorGroups.js` остались абсолютные
  адреса `http://127.0.0.1:8000`. При открытии сайта не с localhost назначение
  врача не сработает; эти запросы нужно перевести на относительные пути
  (`/api/...`) или на `REACT_APP_BASE_URL`.
- Порт `8001` публикуется наружу напрямую. Для production его лучше не
  публиковать, оставив доступ к backend только через nginx.
