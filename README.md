# hg19 WXS/WGS 胚系易感位点分型流程

主入口是 WDL 1.0 `workflow.wdl`，公共 workflow 名保持 `WxsGermlineHg19`。这是单受检者、双端 FASTQ 的流程：提供 `capture_bed` 时按 WXS 捕获范围运行，省略时按 WGS 主染色体全长范围运行；`target_bed` 不决定模式。各 task 独立放在 `tasks/*.wdl`，辅助程序放在 `scripts/`。

```text
workflow.wdl           主流程与 task imports
tasks/*.wdl            每个分析 task 独立一个文件
scripts/*.py           BED 校验与交付预检
```

## 处理链

```text
已合并 R1/R2 → fastp → 修剪后 R1/R2 ┬→ FastQC
                                   └→ BWA-MEM + samtools sort/index → MarkDuplicatesSpark
                                                                  → BaseRecalibrator → ApplyBQSR
                                                                                       └→ Qualimap
capture_bed（可选）→ WXS 校验和 padding；省略时从 FAI 取 WGS 主染色体全长
                    → 按 XX/XY、PAR 与 chrM 分区
           → 常染色体及启用 X/Y 分区用于 BQSR 训练；完整 BAM 应用校准表
recal BAM + 常染色体分区 → HaplotypeCaller -ERC GVCF → 原有 gVCF/索引
recal BAM + 性染色体分区 → 各倍性 HaplotypeCaller → 分区 gVCF/索引
recal BAM + chrM 分区 → Mutect2 mitochondrial mode → FilterMutectCalls → chrM VCF/索引
target_bed（可选） → 按分区范围核查 → 核基因组 all-sites VCF、chrM 变异子集 VCF
```

`capture_bed` 可选：提供时选择 WXS，定义捕获分析范围和捕获 QC；省略或设为 JSON `null` 时选择 WGS，分析 FAI 中完整的 `chr1`–`chr22`、`chrM` 和倍性已明确的 X/Y 分区。WGS 要求这些主 contig 都存在；`capture_padding` 此时不生效。`target_bed` 可选，只影响下游范围核查和目标派生，不改变 fastp、比对、BQSR 或主调用。两个 BED 都是 hg19 UCSC `chr` 命名、0-based 半开坐标；空字符串不是有效的 WDL `File`。旧参数 `bed_file` **不直接作为 WDL 输入**；迁移时只能映射到 `capture_bed`，并需在提交层拒绝两者冲突。

设置 `sex_chromosome_complement=XX` 或 `XY` 才启用性染色体调用；默认 `UNKNOWN` 仅调用常染色体及范围内 chrM，X/Y 写入排除清单。XX 的 X 为二倍体，Y 排除；XY 的 X PAR 为二倍体、X 非 PAR 与 Y 非 PAR 为单倍体，Y PAR 因与 X 同源而排除。跨 Y PAR 边界时仅将实际 PAR 片段列入排除清单。GRCh37 PAR 使用固定坐标，并检查 FAI 中 X/Y 长度。BQSR 从常染色体及启用 X/Y 分区的并集训练；常染色体 gVCF 接口保持独立，性染色体另输出分区 gVCF，不能将它们当作一个已合并文件。WXS 的捕获 BED 仍须有常染色体区间。其它 contig、部分范围外目标及 Y PAR 均显式记录；CNV/STR/HLA、非 XX/XY 核型和复杂事件尚未实现。

WXS 的 `capture_bed` 含 `chrM` 或进入 WGS 模式时启用独立线粒体分支，先核对 FAI 中 hg19 UCSC `chrM` 长度为 16,571 bp，再对选定范围运行 Mutect2 mitochondrial mode 与 FilterMutectCalls；此分支与 XX/XY 设置无关。线粒体不参与 BQSR 训练，但使用完整 BAM 上已应用的校准表。chrM VCF 保留候选变异及其 FILTER 标记，未做 PASS-only 筛选；未输出位置不表示参考型。当前没有环状基因组断点移位重比对、NuMT 专项验证、异质性阈值与逐位点放行规则，结果只作中间分析，不能用于报告。

重复标记策略面向普通杂交捕获文库；扩增子或 UMI 文库尚无相应引物/UMI 处理，不应直接套用。

## 输入与运行

需要 Cromwell 支持 WDL 1.0，并由运行后端本地化 `File` 输入、`tasks/` 下的 WDL imports 及 Docker 镜像。六张镜像的默认标签均指向 `crpi-xvcezojsbq275htp.cn-shanghai.personal.cr.aliyuncs.com/nap_hub/`，WDL 和 Choppy `defaults`/`inputs` 使用相同值；六档 `cpu*mem*_cluster_config` 名称及 ECS 默认值参考 [hg38 instant defaults](https://github.com/CyanZRoy/wxs_somatic_gatk_hg38_instant/blob/main/defaults)，各 task 使用的实例配置见其 `runtime.instanceTypes`。部署前须逐个拉取并在容器内检查软件、版本和路径：`fastp_image` 需 `fastp`，`fastqc_image` 需 `fastqc`，`analysis_image` 需 `bwa`、`samtools`、`gatk`，`gatk_image` 需 `gatk` 与 `samtools`，`qualimap_image` 需 `qualimap`、`awk`、`tar`、Java，`python_image` 需 Python 3 标准库。所有容器还需满足任务 Shell 命令。镜像标签和资源 URI 不代表已经通过拉取或运行验证；部署时应记录镜像 digest、工具版本和真实路径。

各 task 先将计算所需输入及索引从挂载目录复制到独立的 `/tmp` 目录，在本地运行并把 WDL 输出复制回调用目录；`ValidateInputs` 只对大型 FASTQ 做非空预检。任务退出时另存 `script.txt`、`stdout.txt`、`stderr.txt`，便于在 Choppy 直接打开。当前重任务的 `systemDisk` 使用 150–500 GB 静态初值，需按实际 FASTQ/BAM 大小、本地副本和后端磁盘模型调整；它不是通用容量保证。

主要输入：

| 参数 | 说明 |
| --- | --- |
| `sample_id`、`library_id`、`platform` | 样本级 RG 身份字段；只接受字母、数字、下划线、点和连字符 |
| `fastq_r1`、`fastq_r2` | 上游已合并的单对 R1/R2 FASTQ；WDL 类型均为 `File` |
| `capture_bed` | 可选；有值为 WXS 实际试剂捕获范围，省略或 `null` 为 WGS |
| `sex_chromosome_complement` | `XX` / `XY` / `UNKNOWN`；须依据已确认的样本信息设置，不能由未验证的覆盖率推断 |
| `target_bed` | 可选，省略或 JSON `null`；空字符串不是有效 BED |
| `ref_fasta`、`ref_fai`、`ref_dict`、`bwa_index_files` | 同一 hg19 UCSC FASTA 的完整索引组；BWA 顺序为 `.amb/.ann/.bwt/.pac/.sa` |
| `dbsnp_vcf/index`、`mills_vcf/index` | 同版 BQSR known-sites 与索引 |
| `intervals_script`、`delivery_script` | 随 WDL 包一起可被 Cromwell 本地化的两个 `scripts/*.py` 文件 |

在仓库外创建 `inputs.json`，填入真实样本和 hg19 UCSC 参考文件的可访问路径。以下是最小输入骨架；五个 BWA 索引、FAI、字典和 known-sites 索引须与 FASTA 匹配。`capture_bed` 未填时为 WGS；WXS 在 JSON 中另加 `"WxsGermlineHg19.capture_bed": "/path/to/capture.bed"`。可选目标清单用 `target_bed`；确认 XX/XY 后再设置 `sex_chromosome_complement`。两个 Python 路径必须能被运行后端本地化。

```json
{
  "WxsGermlineHg19.sample_id": "SAMPLE_ID",
  "WxsGermlineHg19.library_id": "LIBRARY_ID",
  "WxsGermlineHg19.fastq_r1": "/path/to/merged_R1.fastq.gz",
  "WxsGermlineHg19.fastq_r2": "/path/to/merged_R2.fastq.gz",
  "WxsGermlineHg19.ref_fasta": "/path/to/ucsc.hg19.fa",
  "WxsGermlineHg19.ref_fai": "/path/to/ucsc.hg19.fa.fai",
  "WxsGermlineHg19.ref_dict": "/path/to/ucsc.hg19.dict",
  "WxsGermlineHg19.bwa_index_files": ["/path/to/ucsc.hg19.fa.amb", "/path/to/ucsc.hg19.fa.ann", "/path/to/ucsc.hg19.fa.bwt", "/path/to/ucsc.hg19.fa.pac", "/path/to/ucsc.hg19.fa.sa"],
  "WxsGermlineHg19.dbsnp_vcf": "/path/to/dbsnp_138.hg19.vcf",
  "WxsGermlineHg19.dbsnp_index": "/path/to/dbsnp_138.hg19.vcf.idx",
  "WxsGermlineHg19.mills_vcf": "/path/to/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf",
  "WxsGermlineHg19.mills_index": "/path/to/Mills_and_1000G_gold_standard.indels.hg19.sites.vcf.idx",
  "WxsGermlineHg19.intervals_script": "/path/to/scripts/intervals.py",
  "WxsGermlineHg19.delivery_script": "/path/to/scripts/delivery.py"
}
```

先用 WOMtool 校验 WDL；将 `tasks/` 打包为 imports ZIP 后提交给 Cromwell：

```bash
java -jar womtool.jar validate workflow.wdl
python3 -m zipfile -c imports.zip tasks
java -jar cromwell.jar run workflow.wdl --inputs inputs.json --imports imports.zip
```

## 输出及语义

每次运行输出常染色体原生 `sample.g.vcf.gz` 和 `.tbi`、总 `analysis_intervals_bed`、`bqsr_intervals_bed`、`autosomal_intervals_bed`、X/Y 与 chrM 分区 BED、`excluded_capture_intervals_tsv`、`sample_qc_json`、`run_manifest_json`，并保留 recal BAM/BAI、fastp/FastQC、重复标记和 Qualimap 报告。XX/XY 有相应范围时，另输出 `x_diploid_gvcf`、`x_haploid_gvcf`、`y_haploid_gvcf` 中适用的文件及索引；chrM 有分析范围时另输出 `mt_unfiltered_vcf`、`mt_mutect_stats`、`mt_vcf` 和索引。无区间者为 null。核基因组 gVCF 含参考块及 `<NON_REF>`，不能按普通逐位点 VCF 解读。QC/manifest 的 `analysis_mode` 为 `WXS` 或 `WGS`；WGS 无捕获 BED 哈希，Qualimap 执行全 BAM QC。

有 `target_bed` 时额外输出 `target_scope_tsv`、常染色体 `target_in_scope_bed`；有范围内目标的核基因组分区各自输出 all-sites VCF/索引，chrM 输出带 FILTER 标记的变异子集 `mt_target_regions_vcf`/索引。它们是 GATK 的**原始派生中间结果**，不是完整检测清单交付 VCF；`target_scope_tsv` 只说明请求范围与调用范围的关系，不包含可靠 GT、精确位点深度或最终位点 QC。完全范围外时对应分区 VCF 为 null。当前不生成 `sample.targets.vcf.gz` 或逐目标最终 TSV，不能把未输出行推断成 `0/0`。

`sample_qc_json` 中 `format_precheck_passed=true` 仅说明初步文件检查完成；`ready_for_import_test=false`、`ready_for_report=false` 在本版本固定。完整索引查询、样本身份、捕获性能、污染、逐位点质量、参考型证据和报告系统接口尚需验证。主 gVCF 无目标清单时，目标计数为 null。

## 开发验收状态

- 已完成：WDL 任务连接、按可选捕获 BED 选择 WXS/WGS 范围、常染色体与 XX/XY 性染色体分区、范围内 chrM 候选变异分支、检测 BED 参数隔离、单对 FASTQ 输入、保守交付元数据、小型辅助脚本测试。
- 已在本机 Ubuntu-24.04 WSL 用 WOMtool 81 校验主 WDL 和全部 imports；未完成 Choppy 渲染与后端资源配置、容器集成、真实 FASTQ 冒烟、PAR 边界和 X/Y 同源区域的真实样本 QC、线粒体断点/NuMT/异质性验证、目标事件级完整性与临床放行验证。

## 参考实现

本流程独立实现单样本胚系核基因组分支；线粒体候选变异分支使用 [GATK Mutect2 mitochondrial mode](https://gatk.broadinstitute.org/hc/en-us/articles/9570422171291-Mutect2)。GATK 的单样本 GenotypeGVCFs 输入和 `--include-non-variant-sites` 用法见 [官方文档](https://gatk.broadinstitute.org/hc/en-us/articles/360056970432-GenotypeGVCFs)。
