# Changelog

## 2026-10-22

- 在 Ubuntu-24.04 WSL 的公共只读路径 `/opt/cromwell/81/` 安装 Cromwell 81 和 WOMtool 81；用 WOMtool 校验主 WDL 及全部 15 个 imports，通过 `Success!`。
- 新增 Windows Codex 可直接调用的 `scripts/validate_wdl_wsl.ps1`，并将每次 WDL 修改后的实际 WOMtool 校验写入工程说明。

## 2026-10-21

- 修复四个 WDL task 中输入、输出同名导致的 Cromwell import 失败：输入改用 `input_*`，同步主 workflow 调用参数，保留既有输出接口；新增静态接口回归测试。
- 将六张默认镜像切换到项目指定的阿里云 `nap_hub` 仓库，保留原工具镜像标签版本，并同步 WDL、Choppy `defaults` 和部署说明；镜像可拉取性与内容仍待运行节点验证。
- 将 `small/medium/large_cluster` 替换为参考 hg38 instant `defaults` 的六档 `cpu*mem*_cluster_config` 名称和值，按任务分配实例并让 fastp 默认使用 8 线程。
- 更新 Git 发布允许列表，使 Choppy 配置、部署文档和公开维护记录能够随仓库交付；本地研究 `doc/` 继续忽略。
- 扩充运行依赖文档：逐项核对上游固定提交的镜像调用，标明本仓库新增的 Python 镜像，补充拉取、离线转运、digest、容器内软件/包/路径及小样本验收步骤；修正 GATK 镜像须有 samtools 的依赖和 WGS chrM 输出说明。
- `capture_bed` 改为可选：提供时按 WXS 捕获范围运行，省略时从 FAI 生成 chr1–chr22、chrM 及适用 X/Y 全长 WGS 区间；保持 workflow 公共名不变。
- WGS 模式下 Qualimap 不传捕获 GFF，目标范围表将 `outside_capture` 标为 `not_applicable`，QC/manifest 记录 `analysis_mode=WGS`；Choppy 表单与模板支持省略 BED。
- 增加捕获范围内 hg19 UCSC `chrM` 分区、Mutect2 mitochondrial mode 与 FilterMutectCalls 候选变异分支，支持可选目标 BED 的线粒体变异子集、交付预检和哈希记录。
- 单独输出 BQSR 训练 BED（常染色体及启用的 X/Y 分区），将 chrM 排除出训练但继续对完整 BAM 应用校准表；验证 chrM FAI 长度为 16,571 bp。
- 将 BQSR 训练区间接到常染色体与启用的 X/Y 调用分区并集，避免性染色体捕获区间只依赖常染色体训练范围。
- 修正 XY 样本 chrY 捕获区间跨 PAR 边界时的排除区间、计数和目标状态；排除清单仅列出实际排除的 PAR 片段。
- 补齐性染色体分区测试，并同步 README、部署说明和后续验收项。

## 2026-10-20

- 新建 WDL 1.0 `WxsGermlineHg19` 初版：单对已合并 R1/R2 FASTQ 预处理、常染色体捕获范围的 HaplotypeCaller gVCF、可选目标 BED 派生。
- 加入 BED 校验、范围状态、保守 QC/manifest 脚本及输入示例。
- 加入 Choppy 单对 FASTQ 参数模板草案和单样本表单；尚未在平台渲染或执行。
- 按上游仓库形式将 task 拆到 `tasks/*.wdl`，根目录 `workflow.wdl` 只保留 imports 和调度；移除 lane scatter 与 BAM 合并 task。
- 增加可随仓库发布的 `docs/流程与运行依赖.md`，扩充 `.gitignore` 以排除本地环境、运行结果和真实样本文件。
