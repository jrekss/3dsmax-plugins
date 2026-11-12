# 3ds Max Plugins & Scripts Collection

Личная коллекция плагинов, модификаторов и скриптов для **Autodesk 3ds Max** (включая нативные C++ плагины `.dlm` под 3ds Max 2027 SDK и MAXScript-утилиты).

## Содержимое коллекции

### Плагины и модификаторы (`plugins/`)
| Название | Описание |
| :--- | :--- |
| **[FloorGenerator-Pro](plugins/FloorGenerator-Pro/)** | Нативный C++ модификатор (`.dlm`) + MAXScript v2.10. 7 паттернов укладки (`Standard`, `Herringbone`, `Chevron`, `Basket Weave`, `Hexagon`, `Triangle`, `Octagon`), `Spread`-распределение, фаски, UVW-развёртка и `.ini`-пресеты. |
| **[Collect-Assets](plugins/Collect-Assets/)** | Сбор и упаковка всех текстур, прокси и ассетов сцены 3ds Max в единый архив/папку. |
| **[batchcam2027](plugins/batchcam2027/)** | Batch Camera Render — пакетный рендер камер и сцен в 3ds Max. |

### Скрипты и утилиты (`scripts/`)
*Раздел для отдельных `.ms` / `.mzp` инструментов.*

---

## Быстрая сборка C++ плагинов
Для сборки `.dlm` под **3ds Max 2027** перейдите в папку нужного плагина и запустите `build_dlm.bat` (требуются *Visual Studio 2022 Build Tools*, *CMake* и *3ds Max 2027 SDK*).
