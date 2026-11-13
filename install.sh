#!/bin/bash
# ocr-small — установка зависимости (идемпотентно). Всё лежит рядом в папке плагина, копирование — только в systemd/niri.
set -euo pipefail
PLUGIN_DIR="$HOME/.config/angelos/plugins/ocr-small"
MODEL="$PLUGIN_DIR/ct2-en-ru"
MODEL_REV="66f1027eb3d27d8f85c9f0496d7e0b7829c07504"
declare -A MODEL_SHA256=(
  [config.json]=8f6496adfc930cbfecbe8281112197705c488fab47d34b4829b06d7f478909af
  [model.bin]=f5ae1da30bcb61e877c549be8fb5a434193893eb97509ccd0b954465f9a8f80c
  [shared_vocabulary.json]=bf1812383ed402163a2ed1b553e175e7db96a54ed68b6c15566018fdf945ed99
  [source.spm]=16bebef1389a0b8ab452772c4e35b9e605e5713f8ac7baa71ca701394eaa086d
  [target.spm]=745998e51ba5b058e38b7ac7765c25c43ed5c1c39cc92b27163b9b2e323c9d7c
)

# ZIP из Store теряет +x — возвращаем права лаунчерам
chmod +x "$PLUGIN_DIR/ocr-region-local" "$PLUGIN_DIR/install.sh" 2>/dev/null || true

for cmd in python3 slurp grim wl-copy ollama curl sha256sum; do
  command -v "$cmd" >/dev/null || { echo "❌ Нет команды: $cmd"; exit 1; }
done

if [ ! -x "$PLUGIN_DIR/translate-venv/bin/python" ]; then
  if command -v uv >/dev/null; then
    uv venv "$PLUGIN_DIR/translate-venv" --python 3.14
    uv pip install --python "$PLUGIN_DIR/translate-venv/bin/python" ctranslate2 sentencepiece
  else
    python3 -m venv "$PLUGIN_DIR/translate-venv"
    "$PLUGIN_DIR/translate-venv/bin/pip" install ctranslate2 sentencepiece
  fi
else echo "скип: venv перевода (210 МБ)"; fi

model_ready=1
for f in "${!MODEL_SHA256[@]}"; do
  if [ ! -f "$MODEL/$f" ] || ! echo "${MODEL_SHA256[$f]}  $MODEL/$f" | sha256sum -c --status; then
    model_ready=0
  fi
done

if [ "$model_ready" -eq 0 ]; then
  mkdir -p "$MODEL"
  for f in "${!MODEL_SHA256[@]}"; do
    tmp="$MODEL/$f.tmp"
    curl -fsSL -A Mozilla "https://huggingface.co/jiangzhuo9357/opus-mt-en-ru-ct2/resolve/$MODEL_REV/$f" -o "$tmp"
    echo "${MODEL_SHA256[$f]}  $tmp" | sha256sum -c -
    mv -f -- "$tmp" "$MODEL/$f"
  done
else echo "скип: проверенная CT2-модель EN→RU (79 МБ)"; fi

SVC="$HOME/.config/systemd/user/ollama-ocr.service"
if [ ! -f "$SVC" ]; then
  cp "$PLUGIN_DIR/ollama-ocr.service" "$SVC"
  systemctl --user daemon-reload
  systemctl --user enable --now ollama-ocr.service
else echo "скип: ollama-ocr.service (OLLAMA_KEEP_ALIVE=10m)"; fi

if ! grep -q "Mod+Shift+T" "$HOME/.config/niri/cfg/user.kdl" 2>/dev/null; then
  printf '\n// Region OCR: select a rectangle and copy its text using local Ollama GLM-OCR.\nbinds {\n    Mod+Shift+T repeat=false hotkey-overlay-title="OCR GLM: область → буфер" { spawn-sh "exec ~/.config/angelos/plugins/ocr-small/ocr-region-local"; }\n}\n' >> "$HOME/.config/niri/cfg/user.kdl"
  echo "бинда Mod+Shift+T добавлена — перелогинься или systemctl --user reload niri.service"
fi
echo "Готово. Проверь: ollama ps, niri validate, Mod+Shift+T"
