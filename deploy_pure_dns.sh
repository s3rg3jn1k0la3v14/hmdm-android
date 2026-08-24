#!/usr/bin/env bash
set -e

echo "[*] PURE DPM EXPERIMENT: PRIVATE DNS ENFORCEMENT"

# 1. Проверка окружения
if ! command -v git &> /dev/null || ! command -v gh &> /dev/null || ! command -v perl &> /dev/null; then
    echo "[!] Ошибка: Требуются git, gh и perl."
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo "[!] Ошибка: GitHub CLI не авторизован."
    exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
ENFORCER_DIR="app/src/main/java/com/hmdm/launcher"
ENFORCER_FILE="$ENFORCER_DIR/DnsPolicyEnforcer.java"
ADMIN_RECEIVER="app/src/main/java/com/hmdm/launcher/AdminReceiver.java"
BOOT_RECEIVER="app/src/main/java/com/hmdm/launcher/receiver/BootReceiver.java"

# 2. Создание изолированного класса (идемпотентно)
if [ ! -f "$ENFORCER_FILE" ]; then
    echo "[*] Генерация $ENFORCER_FILE..."
    cat << 'EOF' > "$ENFORCER_FILE"
package com.hmdm.launcher;

import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.os.UserManager;
import android.util.Log;

public class DnsPolicyEnforcer {
    private static final String TAG = "HMDM-DNS";

    public static void enforceDevicePolicies(Context context) {
        try {
            DevicePolicyManager dpm = (DevicePolicyManager) context.getSystemService(Context.DEVICE_POLICY_SERVICE);
            if (dpm == null) {
                Log.e(TAG, "DevicePolicyManager == null");
                return;
            }

            if (!dpm.isDeviceOwnerApp(context.getPackageName())) {
                Log.e(TAG, "Application is NOT Device Owner. Cannot enforce policies.");
                return;
            }

            ComponentName admin = new ComponentName(context, AdminReceiver.class);
            Log.i(TAG, "Attempting to set DISALLOW_CONFIG_PRIVATE_DNS...");

            dpm.addUserRestriction(admin, UserManager.DISALLOW_CONFIG_PRIVATE_DNS);

            boolean applied = dpm.getUserRestrictions(admin)
                    .getBoolean(UserManager.DISALLOW_CONFIG_PRIVATE_DNS, false);

            if (applied) {
                Log.i(TAG, "SUCCESS: Private DNS restriction VERIFIED active in DPM!");
            } else {
                Log.e(TAG, "FAIL: Private DNS restriction NOT PRESENT after setting it. OEM blocked it?");
            }
        } catch (Throwable e) {
            Log.e(TAG, "CRITICAL: Failed to apply Private DNS restriction", e);
        }
    }
}
EOF
else
    echo "[*] Файл $ENFORCER_FILE уже существует, пропускаем генерацию."
fi

# 3. Точечные хуки с защитой от изменения сигнатур и идемпотентностью.
# ВАЖНО: каждый hook имеет собственный marker, иначе второй вызов для
# AdminReceiver был бы пропущен после первого hook.
inject_hook() {
    local file=$1
    local method_regex=$2
    local marker=$3

    if [ ! -f "$file" ]; then
        echo "[!] Файл $file не найден, пропускаем."
        return 0
    fi

    if grep -q "$marker" "$file"; then
        echo "[*] Хук уже присутствует в $file, пропускаем инъекцию."
        return 0
    fi

    echo "[*] Внедрение хука в $file..."

    perl -0777 -pi -e "s/($method_regex)/\$1\n        try { com.hmdm.launcher.DnsPolicyEnforcer.enforceDevicePolicies(\$2); } catch(Throwable t) { android.util.Log.e(\"HMDM-DNS\", \"$marker\", t); }/g" "$file"

    if ! grep -q "$marker" "$file"; then
        echo "[!] ОШИБКА: Регулярное выражение не нашло метод в $file. Сигнатура изменена."
        exit 1
    fi
}

ADMIN_ENABLED_REGEX='(public\s+void\s+onEnabled\s*\(\s*Context\s+([a-zA-Z0-9_]+)\s*,\s*Intent\s+[^)]+\)\s*\{)'
ADMIN_PROV_REGEX='(public\s+void\s+onProfileProvisioningComplete\s*\(\s*Context\s+([a-zA-Z0-9_]+)\s*,\s*Intent\s+[^)]+\)\s*\{)'
BOOT_RECEIVER_REGEX='(public\s+void\s+onReceive\s*\(\s*Context\s+([a-zA-Z0-9_]+)\s*,\s*Intent\s+[^)]+\)\s*\{)'

inject_hook "$ADMIN_RECEIVER" "$ADMIN_ENABLED_REGEX" "HMDM-DNS-HOOK-ONENABLED"
inject_hook "$ADMIN_RECEIVER" "$ADMIN_PROV_REGEX" "HMDM-DNS-HOOK-PROVISIONING"
inject_hook "$BOOT_RECEIVER" "$BOOT_RECEIVER_REGEX" "HMDM-DNS-HOOK-BOOT"

# 4. Безопасная индексация Git
echo "[*] Индексация измененных файлов..."
git add "$ENFORCER_FILE"
[ -f "$ADMIN_RECEIVER" ] && git add "$ADMIN_RECEIVER"
[ -f "$BOOT_RECEIVER" ] && git add "$BOOT_RECEIVER"

if git diff --cached --quiet; then
    echo "[*] Изменений для коммита нет. Переходим к сборке..."
else
    echo "[*] Коммит изменений..."
    git commit -m "test(dpm): inject pure private DNS restriction policy via DO"
    echo "[*] Пуш в $CURRENT_BRANCH..."
    git push origin "$CURRENT_BRANCH"
fi

# 5. Запуск CI/CD с защитой от Race Condition
WORKFLOW_FILE=$(find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print -quit 2>/dev/null | xargs -r basename)

if [ -z "$WORKFLOW_FILE" ]; then
    echo "[!] Ошибка: Не найден файл рабочего процесса (.github/workflows/*.yml или *.yaml)."
    exit 1
fi

START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "[*] Запуск workflow $WORKFLOW_FILE (Timestamp: $START_TIME)..."
gh workflow run "$WORKFLOW_FILE" --ref "$CURRENT_BRANCH"

echo "[*] Ожидание инициализации сборки в GitHub Actions..."
RUN_ID=""
for i in {1..20}; do
    sleep 3
    RUN_ID=$(gh run list \
        --workflow "$WORKFLOW_FILE" \
        --branch "$CURRENT_BRANCH" \
        --created ">=$START_TIME" \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId')

    if [ -n "$RUN_ID" ]; then
        break
    fi
    echo "    ... ожидание ответа API ($i/20)"
done

if [ -z "$RUN_ID" ]; then
    echo "[!] Не удалось захватить Run ID. Сборка вероятно идет, проверьте репозиторий вручную."
    exit 0
fi

echo "[*] Сборка захвачена. Run ID: $RUN_ID"
echo "[*] Подключение к логам потока..."
gh run watch "$RUN_ID" --exit-status

echo "==================================================="
echo "[✔] ДЕПЛОЙ ЗАВЕРШЕН."
echo "[✔] Скачать APK: https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/actions/runs/$RUN_ID"
