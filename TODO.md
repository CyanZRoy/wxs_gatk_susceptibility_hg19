# 后续工作

1. 在目标 Cromwell/Choppy 后端渲染 `inputs`、验证依赖 ZIP 提交，并核对六档 `runtime.instanceTypes` 的实际可用性、Docker 与 OSS File 本地化。本地 WSL WOMtool 81 已校验主 WDL 和 15 个 task imports；目标后端仍须复核。
2. 核实 hg19 FASTA/BWA/FAI/字典和 known-sites 索引的实际路径、校验和、contig；在目标后端从 `nap_hub` 逐一拉取六张镜像，检查仓库权限、平台、digest、Shell、程序/包/路径/版本及最小任务运行，重点确认 `analysis_image` 的 GATK 和 `gatk_image` 的 samtools，再固定已验证的 digest。
3. 用小型双端 FASTQ、真实 WXS 与 WGS 样本分别完成有/无 `capture_bed`、有/无 `target_bed` 的端到端运行，确认全长主染色体区间、gVCF 索引、参考块、Qualimap 模式、QC 与参数隔离；按 WGS 数据量重新评估磁盘、内存和运行时长。
4. 用已确认 XX/XY 样本验证 X/Y PAR 边界、非 PAR 倍性、X/Y 同源区域错配、覆盖率和 gVCF 索引查询；评估非 XX/XY 核型的处理策略。现有性染色体分区仅为中间分析结果，不能直接报告。
5. 用含 chrM 捕获探针的 WXS 样本、WGS 样本及参考材料分别验证 hg19 UCSC chrM 序列/坐标、Mutect2/FilterMutectCalls 版本兼容、覆盖率、环状断点移位重比对、NuMT 错配、异质性检出阈值、假阳性与正交确认；两种模式的性能结论须分别建立。
6. 设计目标事件 manifest、跨边界 Indel/删除处理、逐位点 BAM 证据、显式 no-call、目标 VCF/TSV 与放行规则；未验证前保持 `ready_for_report=false`。
7. 验证报告系统 gVCF 导入，包括索引查询、参考块中间位置、`<NON_REF>`、低覆盖和范围外状态；通过后才调整 `ready_for_import_test`。
8. 在提交层验证上游交付的已合并 R1/R2 与样本 ID 的对应关系，并实现旧 `bed_file` 到 `capture_bed` 的唯一映射及冲突拒绝。
9. 扩充运行 manifest：原始 OSS URI、参考 FASTA 哈希、镜像 digest、实际工具版本、Cromwell 运行 ID、可选派生产物哈希及完整索引查询结果。
