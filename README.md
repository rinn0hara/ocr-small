# OCR Small — плагин angelOS

Локальное распознавание текста с экрана без облака: выдели область — текст в буфер, поверх экрана маленькая карточка с оригиналом и кнопкой офлайн-перевода EN→RU.

**Что делает**

```
Mod+Shift+T ─ slurp ─ grim ─ ollama_ocr.py ─ 127.0.0.1:11434/api/chat (glm-ocr, Vulkan GPU)
                                          ├─ wl-copy (оригинал в буфер)
                                          └─ $XDG_RUNTIME_DIR/ocr-small/ocr.json + qs ipc call ocrSmall openCard
                                               └─ QML PanelWindow Overlay (поверх окон, как Mod+Shift+S)
По кнопке EN→RU: QML Process (stdin) ─ translate_en_ru.py ─ CT2 MarianMT (CPU) ─ русский текст
```

Карточка — не отдельное окно `FloatingWindow`, а `PanelWindow` с `WlrLayershell.layer: Overlay` (`angelos-ocr-small`), внизу-справа сфокусированного экрана. Клики вне карточки проходят в приложения, клавиатура — `OnDemand`.

**Стек**

| Слой | Технология | Почему**
|---|---|---|
| OCR | Ollama `glm-ocr:latest` (GLM-OCR 0.9B + vision projector), `OLLAMA_VULKAN=1`, `OLLAMA_HOST=127.0.0.1:11434` | локально, понимает русский и английский, держит модель в VRAM |
| Перевод | `Helsinki-NLP/opus-mt-en-ru` через CTranslate2 (`jiangzhuo9357/opus-mt-en-ru-ct2`, int8, CPU) | без `argos-translate` — свежий Argos тянет `torch/spaCy/stanza` (~5.7 ГБ), мы — только `ctranslate2+sentencepiece` (~210 МБ) |
| UI | AngelOS плагин (`main: Main.qml`, `IpcHandler target ocrSmall: openCard/closeCard`) | заголовок, кнопки, `wl-copy` оригинала/перевода |

Argos Translate — Python-библиотека офлайн-перевода на той же MarianMT. Сюда не берём: её актуальная версия (1.11.0) тянет зависимости весом в Гб. Наш скрипт — Direct CT2, те же веса, но лёгкий.

**Сколько весит и что нужно**

| Что | Размер | Где лежит |
|---|---|---|
| Плагин `ocr-small` | 12 КБ | `~/.config/angelos/plugins/ocr-small/` |
| `glm-ocr:latest` | 2.7 ГБ на диске, ~2.0 ГБ в VRAM при активном runner | `/var/lib/ollama` (user-сервис `ollama-ocr.service`, `OLLAMA_MODELS=/var/lib/ollama`) |
| CT2-модель EN→RU | 79 МБ (model.bin 75 МБ) | `~/.config/angelos/plugins/ocr-small/ct2-en-ru/` |
| Venv перевода | 210 МБ (`ctranslate2` 67 МБ + `ctranslate2.libs` 80 МБ) | `~/.config/angelos/plugins/ocr-small/translate-venv/` |

Зависимости: `slurp`, `grim`, `wl-copy`, `python3`, Ollama (+ `ollama-vulkan` для NVIDIA), Wayland/niri, angelOS/Quickshell. VRAM: RTX 3050 6 ГБ хватает (100% GPU, `ollama ps` показывает glm-ocr ~2 ГБ). OCR-скрипта — 4 КБ, переводчик — 2 КБ.

Модель держится в VRAM `OLLAMA_KEEP_ALIVE=10m` (в сер­висе) и `"keep_alive": "30m"` в запросе — уменьшаешь в одном месте, если мало памяти. Первая загрузка runner в VRAM долгая, повторные быстрые, пока `keep_alive` не истёк.

**Установка (с чистого)**

```bash
# 1) плагин
cp -r ocr-small ~/.config/angelos/plugins/
~/.config/angelos/bin/angelos reload

# 2) зависимости и скрипты
bash ~/.config/angelos/plugins/ocr-small/install.sh

# 3) если glm-ocr нет в /var/lib/ollama — скачай через системный ollama (папка read-only для юзера)
ollama pull glm-ocr   # sudo если нужно
systemctl --user enable --now ollama-ocr.service
niri validate  # проверить конфиг niri
```

`install.sh` идемпотентен: если `ollama-ocr.service` и бинд `Mod+Shift+T` в `~/.config/niri/cfg/user.kdl` уже есть — только пропустит. Всё остальное (venv, модель, скрипты) лежит рядом в папке плагина — в `~/.local` ничего не копируется. Скачивает CT2-модель с Hugging Face, проверяет sha256, создаёт venv через `uv`.

**Использование**

`Mod+Shift+T` — выделить область, Esc — отмена. Карточка открывается сразу после распознавания. В ней: оригинал, **EN → RU**, **Копия оригинала**, **Копия перевода**, крестик и `Esc`. Ошибки OCR не трогают буфер.

Проверка без экрана:

```bash
~/.config/angelos/plugins/ocr-small/ocr-region-local ~/.config/angelos/plugins/ocr-small/bench/corpus/ru-light.png
printf 'The clipboard is ready.' | ~/.config/angelos/plugins/ocr-small/translate-venv/bin/python ~/.config/angelos/plugins/ocr-small/scripts/translate_en_ru.py
```

**Откат**

```bash
rm -rf ~/.config/angelos/plugins/ocr-small
systemctl --user disable --now ollama-ocr.service
# и убрать блок Mod+Shift+T из ~/.config/niri/cfg/user.kdl
```

---

## Проверка и разработка

Плагин можно проверять без изменения dotfiles: положи папку в `~/.config/angelos/plugins/ocr-small/`, затем выполни `~/.config/angelos/bin/angelos reload`. В **Настройки → Плагины** проверь, что он обнаружен, и переключи его выключить/включить. Для полного функционального теста установи зависимости командой выше, затем выдели область через `Mod+Shift+T`; `Esc` отменяет выбор.

Локальные проверки из корня плагина:

```bash
jq empty manifest.json
bash -n install.sh ocr-region-local
translate-venv/bin/python -m unittest discover -s scripts -v
```

Для OCR без захвата экрана передай тестовую картинку: `./ocr-region-local bench/corpus/ru-light.png`. Перевод проверяется после установки venv командой `translate-venv/bin/python scripts/translate_en_ru.py --selftest`. Реальный UI следует проверить на обеих темах AngelOS; карточка использует штатные Theme-токены и `PanelWindow` Overlay.

## Публикация в Community Store

Исходники хранятся отдельно от dotfiles. Release ZIP содержит эту папку и ровно один `manifest.json`; `translate-venv/` и `ct2-en-ru/` в архив не входят. Опубликуй ZIP как GitHub Release asset с версией из манифеста, затем добавь в `angelos-community-registry/plugins.json` запись со ссылкой на asset, его SHA-256, зависимостями и разрешениями (`status: pending`) и открой PR. Подробности: [гайд публикации](https://github.com/futureUnd1ground/angelos-community-registry/blob/main/CONTRIBUTING.md).

Плагин работает локально: скриншот передаётся только Ollama на `127.0.0.1:11434`; установщик отдельно скачивает модель перевода с Hugging Face по зафиксированному commit и сверяет SHA-256 всех файлов. `install.sh` не запускается самим Store: пользователь запускает его после установки архива, если хочет настроить OCR. MIT относится к коду плагина. Карточка [оригинальной модели OPUS-MT](https://huggingface.co/Helsinki-NLP/opus-mt-en-ru) указывает Apache-2.0; у [CT2-конверсии](https://huggingface.co/jiangzhuo9357/opus-mt-en-ru-ct2) отдельной карточки/лицензии нет. Веса скачиваются отдельно и в ZIP не входят — эту оговорку стоит включить в PR реестра.
