## Пакеты Picters для Xiaomi 17

| Канал | База | Ядро | Модули и приложение |
| --- | --- | --- | --- |
| **A16** | Linux 6.12.23 · KMI 5 · ReSukiSU | `A16-Kernel.zip` | `A16-OOTMODULES.zip` |
| **A17 — экспериментальный** | Linux 6.12.69 · KMI 6 · ReSukiSU | `A17-Kernel.zip` | `A17-OOTMODULES.zip` |

Поддержка Android 17 новой базой пока не подтверждена. На Android 16 / OS3.0.315.0.WPCCNXM она не загрузилась. Версия Android сама по себе не гарантирует совместимость с vendor-модулями.

Каждый OOT-пакет содержит драйверы **только для своего ядра** и подписанный Picters Modules Manager **1.3.2**. Приложение показывает новые релизы и открывает GitHub; скачивание и установка выполняются вручную. Старый менеджер 1.3.1 не распознаёт новые имена пакетов.

### Установка

1. Скачайте ядро и OOT-пакет из одного релиза своего канала.
2. Установите ядро и загрузите телефон.
3. Установите соответствующий OOT-пакет в KernelSU/Magisk и перезагрузите телефон.

Установщик модулей проверяет точную строку ядра. При смене ядра boot-service пропускает загрузку чужих драйверов. Настройки приложения сохраняются.

### Сборка

`Build A16 and A17 packages` собирает оба канала и сохраняет артефакты без публикации. Для одного канала используйте `Build Kernel`. Все автоматические dispatch-сборки также создают только артефакты.

APK хранится в `assets/` вместе с SHA-256; ключ подписи в репозиторий не попадает. Сборка проверяет SHA-256 и не скачивает APK из отдельного релиза приложения.

Каждая сборка включает `SHA256SUMS`, `build-info.json`, `kmi-report.json` и `RELEASE-NOTES.md`. Заголовки будущих релизов разделены по A16/A17, теги: `A16-YYYYMMDD-HHMM` / `A17-YYYYMMDD-HHMM`. Публикация требует отдельного запуска с разрешённым релизом и подтверждённой совместимостью vendor/ABI.


# Picters Kernel CI Center

CI/CD that builds the **Picters kernel** (with extra out-of-tree modules) and the **Modules pack**
for the **Xiaomi 17 Series** (`sm8850`, *pudding*) — a Rust core (`ci_core`) driving source sync,
toolchain, ReSukiSU/SuSFS, the build and packaging via GitHub Actions.

Each release ships two assets: the flashable kernel (AnyKernel3) and a manager-agnostic
KernelSU/Magisk **Modules pack** (Wi-Fi injection, BT, CAN, SDR/DVB, NTFS). Non-Wi-Fi drivers load
at boot; Wi-Fi injection stays off until switched on in the Picters Modules Manager app.

## Build

Dispatch **Build Kernel** (`project=mi17_sm8850`, `branch=resukisu`) from the Actions tab. After
editing anything under `ci_core_rs/`, run **Build CI Core** first and let it finish.

## Credits

Base CI & kernel: **Kokuban / YuzakiKokuban** · Root: **ReSukiSU / KernelSU** · SuSFS:
**simonpunk** · Injection drivers: **aircrack-ng**, **morrownr**.
