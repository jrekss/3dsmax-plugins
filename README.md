# 3ds Max Plugins & Scripts Collection

Личная коллекция плагинов, модификаторов и скриптов для **Autodesk 3ds Max** (включая нативные C++ плагины `.dlm` под 3ds Max 2027 SDK и MAXScript-утилиты).

## Содержимое коллекции

### Нативные плагины и модификаторы (`plugins/`)
| Название | Версия | Описание |
| :--- | :--- | :--- |
| **[FloorGenerator-Pro](plugins/FloorGenerator-Pro/)** | v2.10 Pro | Нативный C++ модификатор (`.dlm`) + MAXScript-версия. 7 паттернов укладки (`Standard`, `Herringbone`, `Chevron`, `Basket Weave`, `Hexagon`, `Triangle`, `Octagon`), `Spread`-распределение, фаски, UVW-развёртка и `.ini`-пресеты. |

### Скрипты и утилиты (`scripts/`)
*Раздел для отдельных `.ms` / `.mzp` инструментов.*

---

## Быстрая сборка C++ плагинов
Для сборки `.dlm` под **3ds Max 2027** перейдите в папку нужного плагина и запустите `build_dlm.bat` (требуются *Visual Studio 2022 Build Tools*, *CMake* и *3ds Max 2027 SDK*).
