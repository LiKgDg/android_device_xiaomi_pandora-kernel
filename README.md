# pandora-kernel — 提取说明与清单（**本仓不含任何二进制**）

Xiaomi 17 Pro（`pandora` / `canoe` / SM8850）的预编译内核提取规格。
配合 `android_device_xiaomi_pandora` 机型树使用，落到构建树里的路径必须是
`device/xiaomi/pandora-kernel/`。

> **本仓只有清单、校验值与脚本。** 内核二进制是小米的分发物，版权归小米，
> 不随源码分发。你需要从自己的原厂 OTA 自行提取（见下）。

---

## 为什么二进制不入库

| 对象 | 体积 |
|---|---|
| `kernel`（`Image`，GKI 快照） | 41,511,424 B |
| `dtbo.img`（板级专属，pandora 自己的） | 23,068,672 B |
| `dtb/`（12 个 `.dtb`） | 6,557,139 B |
| `vendor_ramdisk/`（461 `.ko` + 6 索引） | 55,134,615 B |
| `vendor_dlkm/`（402 `.ko` + 6 索引） | 137,340,109 B |
| `system_dlkm/`（103 `.ko` + 14 元数据） | 14,643,017 B |
| `system_dlkm_flatten/`（103 `.ko`） | 14,272,380 B |
| **合计** | **292,527,356 B（1112 文件）** |

279 MiB 的二进制放进 git，每次替换模块都要重写历史。而且它本来就该由使用者
从自己手上的固件提取 —— 只有这样才能确认来源。

---

## 内核身份（实测，不是推测）

```
Linux version 6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k
  (kleaf@build-host) ... clang version 19.0.1 ... #1 SMP PREEMPT Tue Sep 8 15:08:49 UTC 2026
```

| 项 | 值 |
|---|---|
| KMI 世代 | **6.12.69-android16-6** |
| 页大小 | 4k（版本串尾部 `-4k`） |
| `kernel` sha256 | `ed9e27aa606772d058684e023fcb2d3dca876505be90227cc8ca5e5d5b95622b` |
| `dtbo.img` sha256 | `751f3ed7c8e22ef2de28ce1b1628f3bd5cea03a09b0070a477a5098e1b2dd09c` |
| `dtbo.img` 大小 | 23,068,672 B（= 机型树 `BOARD_DTBOIMG_PARTITION_SIZE` 的值） |
| 来源固件 | 原厂 OTA `OS4.0.5.0.XBLCNXM`（boot 分区） |

### ⚠️ KMI 约束（本项目踩过的坑，逐字读）

- **内核与模块必须同代**。同一批 `.ko` 必须与 `kernel` 的 KMI 世代一致，
  否则加载时报 `version magic` / `disagrees about version of symbol module_layout`。
- 本项目历史上出现过 **873 个 `.ko` 按 6.12.23 编译、却装入 6.12.69 内核**的事故，
  表现是 `vendor_boot` 的 `modules.load` 150 条**可加载 0 条**，卡开机动画。
- **判据是 `module_layout` 的 CRC，不是 vermagic 字符串**。`CONFIG_MODVERSIONS=y` 时内核的
  `same_magic()` 会跳过 vermagic 前缀比较，只看 CRC。项目既有取证记录的期望值为
  **`0x797f2b3e`**；**本仓未复核该数值**，请用 `scripts/maintain/kmi-gate.sh` 自行验证。
- **本仓清单对应的那套模块，vermagic 是短式 `6.12.69-android16-6-4k`**
  （`vendor_ramdisk` 461 个 + `vendor_dlkm` 402 个全量实测），而 `kernel` 与
  `system_dlkm_flatten/` 下的 GKI 模块是长式
  `6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k`。
  这个字符串差异本身**不是**故障（判据是 CRC），但如果你用自己的提取结果替换，
  请保持"短式归 vendor 侧、长式归 GKI 侧"这个分组，否则 `kmi-gate.sh` 会告警。

---

## 期望的装配布局

```
device/xiaomi/pandora-kernel/
├── kernel                       # Image，41,511,424 B
├── dtbo.img                     # 23,068,672 B
├── dtb/                         # 12 个板级 dtb（00_dtb_*.dtb … 11_dtb_*.dtb）
├── vendor_ramdisk/              # 461 个 .ko
│   ├── modules.load             # 172 行 → 本仓 modules.load.vendor_boot
│   ├── modules.load.recovery    # 466 行 → 本仓 modules.load.recovery
│   ├── modules.alias / modules.dep / modules.softdep / modules.blocklist
├── vendor_dlkm/                 # 402 个 .ko
│   ├── modules.load             # 665 行 → 本仓 modules.load.vendor_dlkm
│   ├── modules.alias / modules.dep / modules.softdep
│   ├── modules.blocklist / system_dlkm.modules.blocklist
├── system_dlkm/                 # kernel/（103 个 .ko）+ 14 个 modules.* 元数据
│   └── modules.load             # 82 行 → 本仓 modules.load.system_dlkm
└── system_dlkm_flatten/         # 103 个 .ko（system_dlkm 的扁平副本）
```

> 注意：实际布局里 `modules.load` **就在目录顶层**，不是 `lib/modules/`。
> 机型树的 `BoardConfig.mk` 读的是 `<dir>/modules.load` 与 `<dir>/modules.load.recovery`。

---

## 如何自行提取

### 1. 解原厂 OTA 全量包

```bash
# 全量包；增量包会被拒绝（退出码 2）
python3 tools/payload_dump.py pandora-ota_full-*.zip stock/ --verify

# 只要这几份时也可以指定分区
python3 tools/payload_dump.py pandora-ota_full-*.zip stock/ boot vendor_boot vendor_dlkm system_dlkm dtbo --verify
```

工具在 `lineage-os-pandora` 主仓的 `tools/` 下。

### 2. 从解出的镜像里取文件

| 目标目录 | 来源分区 | 取什么 |
|---|---|---|
| `vendor_ramdisk/` | `vendor_boot` | ramdisk cpio 里的 `lib/modules/*`（461 个 `.ko` + 6 个 `modules.*` 索引） |
| `vendor_dlkm/` | `vendor_dlkm` | `lib/modules/*`（402 个 `.ko` + 6 个索引） |
| `system_dlkm/` | `system_dlkm` | `lib/modules/<uname -r>/`（103 个 `.ko`）+ 该层 `modules.*` 元数据，**同时**另存一份扁平副本到 `system_dlkm_flatten/` |
| `dtb/` | `boot` 或 `vendor_boot` | 拆分 boot 镜像内 dtb 段（项目脚本 `scripts/maintain/split_dtb.py`） |
| `dtbo.img` | `dtbo` | 整份镜像（保持 23,068,672 B，勿重打包） |
| `kernel` | `boot` | boot 镜像内的 kernel（`Image`） |

> 直接写现成装配脚本是 `scripts/build/make_pandora_kernel.sh`（主仓），上面这张表就是它的产出结构。

### 3. 校验

```bash
./verify.sh /path/to/device/xiaomi/pandora-kernel
```

三步：① `sha256sum -c manifest.sha256`（1112 个文件逐一比对）；
② 四份 `modules.load.*` 的每一条都能在目录里找到对应 `.ko`；
③ 扫 `vendor_ramdisk` + `vendor_dlkm` 的 `.ko`，确认没有残留旧世代（`6.12.23`）。

---

## ⚠️ 别把二进制提交进 git（主仓 `.gitignore` 陷阱）

`lineage-os-pandora` 主仓根 `.gitignore` 里有 `*.img`、`*.ko`、`*.dtb`、`*.zip`。
如果直接把内核目录塞进那个仓库，会发生两件事：

- `dtbo.img` / `*.ko` / `*.dtb` → **全部被忽略**
- `kernel`（无扩展名）→ **不被忽略，会被提交**

结果是"**只有 kernel、没有模块**"的半残提交，而且 `git status` 不会提示你少了东西。
本仓用**独立 `.gitignore`（白名单模式：默认忽略一切，只放行清单与文档）**，并用
`git check-ignore --no-index -v` 逐条验证过。

---

## 清单文件说明

| 文件 | 内容 |
|---|---|
| `manifest.sha256` | 1112 条 `sha256  path`（标准 `sha256sum -c` 格式），顶部 5 行 `#` 注释说明来源与用法 |
| `modules.load.vendor_boot` | 原 `vendor_ramdisk/modules.load`，172 行 |
| `modules.load.recovery` | 原 `vendor_ramdisk/modules.load.recovery`，466 行 |
| `modules.load.vendor_dlkm` | 原 `vendor_dlkm/modules.load`，665 行 |
| `modules.load.system_dlkm` | 原 `system_dlkm/modules.load`，82 行 |
| `verify.sh` | 三步校验脚本 |

产物已实测：665 + 172 条模块清单**每一条都能在对应目录找到实体，悬空 0 条**（本次审计结论）。

---

## 未核实事项

- `module_layout` CRC 是否等于 `0x797f2b3e` —— 未复核，需跑 `scripts/maintain/kmi-gate.sh`
- 这套内核 + 模块组合能否正常启动 —— **未验证**（最近一次刷入停在开机动画）
- `dtb/` 12 棵与 stock dtb 段是否逐字节一致 —— 项目记录为"拼接后与原 dtb 段字节一致"，
  本次审计**未复核该哈希**
- 自行提取得到的 `dtbo.img` 与本仓清单是否一致（取决于你的固件版本）—— 需用 `verify.sh` 比对

---

## 许可证

本仓的脚本与清单文本采用 **Apache License 2.0**（见 `LICENSE`）。
**内核二进制与模块不是本仓内容**，其版权归小米公司，仅用于个人研究；
本仓不包含、也不分发这些二进制。`Xiaomi` 为小米公司商标，本项目与小米公司、
LineageOS 项目均无隶属关系。
