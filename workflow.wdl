version 1.0

import "tasks/validate_inputs.wdl" as validate_inputs
import "tasks/prepare_capture.wdl" as prepare_capture
import "tasks/trim_reads.wdl" as trim_reads
import "tasks/fastqc.wdl" as fastqc
import "tasks/align_reads.wdl" as align_reads
import "tasks/mark_duplicates.wdl" as mark_duplicates
import "tasks/base_recalibrate.wdl" as base_recalibrate
import "tasks/apply_recalibration.wdl" as apply_recalibration
import "tasks/qualimap_qc.wdl" as qualimap_qc
import "tasks/haplotype_gvcf.wdl" as haplotype_gvcf
import "tasks/mitochondrial_variants.wdl" as mitochondrial_variants
import "tasks/prepare_targets.wdl" as prepare_targets
import "tasks/genotype_target_regions.wdl" as genotype_target_regions
import "tasks/select_mt_target_variants.wdl" as select_mt_target_variants
import "tasks/make_delivery.wdl" as make_delivery

workflow WxsGermlineHg19 {
  input {
    String sample_id
    File fastq_r1
    File fastq_r2
    String library_id
    String platform = "ILLUMINA"

    File ref_fasta
    File ref_fai
    File ref_dict
    Array[File]+ bwa_index_files
    File dbsnp_vcf
    File dbsnp_index
    File mills_vcf
    File mills_index
    File? capture_bed
    File? target_bed
    Int capture_padding = 100
    String sex_chromosome_complement = "UNKNOWN"

    File intervals_script
    File delivery_script
    String fastp_image = "crpi-xvcezojsbq275htp.cn-shanghai.personal.cr.aliyuncs.com/nap_hub/fastp:0.19.6"
    String fastqc_image = "crpi-xvcezojsbq275htp.cn-shanghai.personal.cr.aliyuncs.com/nap_hub/fastqc:0.11.8"
    String analysis_image = "crpi-xvcezojsbq275htp.cn-shanghai.personal.cr.aliyuncs.com/nap_hub/sentieon-replaced:2.0"
    String gatk_image = "crpi-xvcezojsbq275htp.cn-shanghai.personal.cr.aliyuncs.com/nap_hub/gatk:4.4.0.0"
    String qualimap_image = "crpi-xvcezojsbq275htp.cn-shanghai.personal.cr.aliyuncs.com/nap_hub/qualimap:2.0.0"
    String python_image = "crpi-xvcezojsbq275htp.cn-shanghai.personal.cr.aliyuncs.com/nap_hub/python:3.11-slim"
    String cpu4mem8_cluster_config = "ecs.e-c1m2.xlarge"
    String cpu4mem16_cluster_config = "ecs.e-c1m4.xlarge"
    String cpu8mem16_cluster_config = "ecs.e-c1m2.2xlarge"
    String cpu16mem32_cluster_config = "ecs.c7a.4xlarge"
    String cpu16mem64_cluster_config = "ecs.u1-c1m4.4xlarge"
    String cpu32mem64_cluster_config = "ecs.u1-c1m2.8xlarge"
    Int threads = 16
  }

  call validate_inputs.ValidateInputs as ValidateInputs {
    input: identity_lines = write_lines([sample_id, library_id, platform]),
      fastq_r1 = fastq_r1, fastq_r2 = fastq_r2,
      bwa_index_files = bwa_index_files, capture_padding = capture_padding,
      docker_image = python_image, cluster_config = cpu4mem8_cluster_config
  }

  call prepare_capture.PrepareCapture as PrepareCapture {
    input: capture_bed = capture_bed, ref_fai = ref_fai,
      capture_padding = capture_padding, script = intervals_script,
      sex_chromosome_complement = sex_chromosome_complement,
      validated = ValidateInputs.marker,
      docker_image = python_image, cluster_config = cpu4mem16_cluster_config
  }

  call trim_reads.TrimReads as TrimReads {
    input: r1 = fastq_r1, r2 = fastq_r2, sample_id = sample_id,
      validated = ValidateInputs.marker, docker_image = fastp_image,
      cluster_config = cpu8mem16_cluster_config, threads = 8
  }
  call fastqc.Fastqc as Fastqc {
    input: r1 = TrimReads.trimmed_r1, r2 = TrimReads.trimmed_r2,
      sample_id = sample_id, docker_image = fastqc_image,
      cluster_config = cpu4mem8_cluster_config, threads = 4
  }
  call align_reads.AlignReads as AlignReads {
    input: r1 = TrimReads.trimmed_r1, r2 = TrimReads.trimmed_r2,
      sample_id = sample_id, library_id = library_id,
      platform = platform, ref_fasta = ref_fasta, ref_fai = ref_fai,
      ref_dict = ref_dict, bwa_index_files = bwa_index_files,
      validated = ValidateInputs.marker,
      docker_image = analysis_image, cluster_config = cpu32mem64_cluster_config, threads = threads
  }
  call mark_duplicates.MarkDuplicates as MarkDuplicates {
    input: input_bam = AlignReads.bam, input_bai = AlignReads.bai,
      sample_id = sample_id, docker_image = analysis_image,
      cluster_config = cpu16mem32_cluster_config
  }
  call base_recalibrate.BaseRecalibrate as BaseRecalibrate {
    input: bam = MarkDuplicates.bam, bai = MarkDuplicates.bai,
      ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
      dbsnp_vcf = dbsnp_vcf, dbsnp_index = dbsnp_index,
      mills_vcf = mills_vcf, mills_index = mills_index,
      calling_bed = PrepareCapture.bqsr_bed,
      sample_id = sample_id, docker_image = gatk_image,
      cluster_config = cpu16mem32_cluster_config
  }
  call apply_recalibration.ApplyRecalibration as ApplyRecalibration {
    input: input_bam = MarkDuplicates.bam, input_bai = MarkDuplicates.bai,
      table = BaseRecalibrate.table, ref_fasta = ref_fasta,
      ref_fai = ref_fai, ref_dict = ref_dict,
      sample_id = sample_id, docker_image = gatk_image,
      cluster_config = cpu16mem32_cluster_config
  }
  call qualimap_qc.QualimapQc as QualimapQc {
    input: bam = ApplyRecalibration.bam, bai = ApplyRecalibration.bai,
      capture_bed = capture_bed, sample_id = sample_id,
      docker_image = qualimap_image, cluster_config = cpu16mem64_cluster_config,
      threads = threads
  }
  call haplotype_gvcf.HaplotypeGvcf as HaplotypeGvcf {
    input: bam = ApplyRecalibration.bam, bai = ApplyRecalibration.bai,
      ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
      calling_bed = PrepareCapture.calling_bed, sample_id = sample_id,
      docker_image = gatk_image, cluster_config = cpu16mem32_cluster_config
  }
  if (PrepareCapture.has_x_diploid) {
    call haplotype_gvcf.HaplotypeGvcf as HaplotypeXDiploid {
      input: bam = ApplyRecalibration.bam, bai = ApplyRecalibration.bai,
        ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
        calling_bed = PrepareCapture.x_diploid_bed,
        sample_id = sample_id + ".x_diploid", ploidy = 2,
        docker_image = gatk_image, cluster_config = cpu16mem32_cluster_config
    }
  }
  if (PrepareCapture.has_x_haploid) {
    call haplotype_gvcf.HaplotypeGvcf as HaplotypeXHaploid {
      input: bam = ApplyRecalibration.bam, bai = ApplyRecalibration.bai,
        ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
        calling_bed = PrepareCapture.x_haploid_bed,
        sample_id = sample_id + ".x_haploid", ploidy = 1,
        docker_image = gatk_image, cluster_config = cpu16mem32_cluster_config
    }
  }
  if (PrepareCapture.has_y_haploid) {
    call haplotype_gvcf.HaplotypeGvcf as HaplotypeYHaploid {
      input: bam = ApplyRecalibration.bam, bai = ApplyRecalibration.bai,
        ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
        calling_bed = PrepareCapture.y_haploid_bed,
        sample_id = sample_id + ".y_haploid", ploidy = 1,
        docker_image = gatk_image, cluster_config = cpu16mem32_cluster_config
    }
  }
  if (PrepareCapture.has_mt) {
    call mitochondrial_variants.MitochondrialVariants as CallMitochondrialVariants {
      input: bam = ApplyRecalibration.bam, bai = ApplyRecalibration.bai,
        ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
        calling_bed = PrepareCapture.mt_bed, sample_id = sample_id,
        docker_image = gatk_image, cluster_config = cpu16mem32_cluster_config
    }
  }
  call make_delivery.MakeDelivery as MakeDelivery {
    input: gvcf = HaplotypeGvcf.gvcf, index = HaplotypeGvcf.index,
      calling_bed = PrepareCapture.calling_bed,
      analysis_bed = PrepareCapture.analysis_bed,
      capture_bed = capture_bed, capture_summary = PrepareCapture.summary,
      target_bed = target_bed,
      sex_chromosome_complement = sex_chromosome_complement,
      x_diploid_gvcf = HaplotypeXDiploid.gvcf,
      x_diploid_index = HaplotypeXDiploid.index,
      x_haploid_gvcf = HaplotypeXHaploid.gvcf,
      x_haploid_index = HaplotypeXHaploid.index,
      y_haploid_gvcf = HaplotypeYHaploid.gvcf,
      y_haploid_index = HaplotypeYHaploid.index,
      mt_vcf = CallMitochondrialVariants.vcf,
      mt_index = CallMitochondrialVariants.index,
      fastp_json = TrimReads.report_json, duplicate_metrics = MarkDuplicates.metrics,
      sample_id = sample_id, script = delivery_script,
      docker_image = python_image, cluster_config = cpu4mem16_cluster_config
  }

  if (defined(target_bed)) {
    call prepare_targets.PrepareTargets as PrepareTargets {
      input: target_bed = select_first([target_bed]), capture_bed = capture_bed,
        calling_bed = PrepareCapture.calling_bed, ref_fai = ref_fai,
        x_diploid_bed = PrepareCapture.x_diploid_bed,
        x_haploid_bed = PrepareCapture.x_haploid_bed,
        y_haploid_bed = PrepareCapture.y_haploid_bed,
        mt_bed = PrepareCapture.mt_bed,
        sex_chromosome_complement = sex_chromosome_complement,
        script = intervals_script, docker_image = python_image,
        cluster_config = cpu4mem16_cluster_config
    }
    if (PrepareTargets.has_in_scope) {
      call genotype_target_regions.GenotypeTargetRegions as GenotypeTargetRegions {
        input: input_gvcf = HaplotypeGvcf.gvcf, input_index = HaplotypeGvcf.index,
          ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
          in_scope_bed = PrepareTargets.in_scope_bed, sample_id = sample_id,
          docker_image = gatk_image, cluster_config = cpu16mem32_cluster_config
      }
    }
    if (PrepareTargets.has_x_diploid) {
      call genotype_target_regions.GenotypeTargetRegions as GenotypeXDiploidTargets {
        input: input_gvcf = select_first([HaplotypeXDiploid.gvcf]),
          input_index = select_first([HaplotypeXDiploid.index]),
          ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
          in_scope_bed = PrepareTargets.x_diploid_in_scope_bed,
          sample_id = sample_id + ".x_diploid", docker_image = gatk_image,
          cluster_config = cpu16mem32_cluster_config
      }
    }
    if (PrepareTargets.has_x_haploid) {
      call genotype_target_regions.GenotypeTargetRegions as GenotypeXHaploidTargets {
        input: input_gvcf = select_first([HaplotypeXHaploid.gvcf]),
          input_index = select_first([HaplotypeXHaploid.index]),
          ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
          in_scope_bed = PrepareTargets.x_haploid_in_scope_bed,
          sample_id = sample_id + ".x_haploid", ploidy = 1, docker_image = gatk_image,
          cluster_config = cpu16mem32_cluster_config
      }
    }
    if (PrepareTargets.has_y_haploid) {
      call genotype_target_regions.GenotypeTargetRegions as GenotypeYHaploidTargets {
        input: input_gvcf = select_first([HaplotypeYHaploid.gvcf]),
          input_index = select_first([HaplotypeYHaploid.index]),
          ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
          in_scope_bed = PrepareTargets.y_haploid_in_scope_bed,
          sample_id = sample_id + ".y_haploid", ploidy = 1, docker_image = gatk_image,
          cluster_config = cpu16mem32_cluster_config
      }
    }
    if (PrepareTargets.has_mt) {
      call select_mt_target_variants.SelectMtTargetVariants as SelectMtTargetVariants {
        input: input_vcf = select_first([CallMitochondrialVariants.vcf]),
          input_index = select_first([CallMitochondrialVariants.index]),
          ref_fasta = ref_fasta, ref_fai = ref_fai, ref_dict = ref_dict,
          in_scope_bed = PrepareTargets.mt_in_scope_bed,
          sample_id = sample_id, docker_image = gatk_image,
          cluster_config = cpu4mem16_cluster_config
      }
    }
  }

  output {
    File gvcf = HaplotypeGvcf.gvcf
    File gvcf_index = HaplotypeGvcf.index
    File analysis_intervals_bed = PrepareCapture.analysis_bed
    File bqsr_intervals_bed = PrepareCapture.bqsr_bed
    File autosomal_intervals_bed = PrepareCapture.calling_bed
    File x_diploid_intervals_bed = PrepareCapture.x_diploid_bed
    File x_haploid_intervals_bed = PrepareCapture.x_haploid_bed
    File y_haploid_intervals_bed = PrepareCapture.y_haploid_bed
    File mt_intervals_bed = PrepareCapture.mt_bed
    File? x_diploid_gvcf = HaplotypeXDiploid.gvcf
    File? x_diploid_gvcf_index = HaplotypeXDiploid.index
    File? x_haploid_gvcf = HaplotypeXHaploid.gvcf
    File? x_haploid_gvcf_index = HaplotypeXHaploid.index
    File? y_haploid_gvcf = HaplotypeYHaploid.gvcf
    File? y_haploid_gvcf_index = HaplotypeYHaploid.index
    File? mt_unfiltered_vcf = CallMitochondrialVariants.unfiltered_vcf
    File? mt_mutect_stats = CallMitochondrialVariants.stats
    File? mt_vcf = CallMitochondrialVariants.vcf
    File? mt_vcf_index = CallMitochondrialVariants.index
    File excluded_capture_intervals_tsv = PrepareCapture.excluded_tsv
    File sample_qc_json = MakeDelivery.qc_json
    File run_manifest_json = MakeDelivery.manifest_json
    File recalibrated_bam = ApplyRecalibration.bam
    File recalibrated_bam_index = ApplyRecalibration.bai
    File duplicate_metrics = MarkDuplicates.metrics
    File fastp_report = TrimReads.report_json
    File fastp_html_report = TrimReads.report_html
    Array[File] fastqc_reports = [Fastqc.html_r1, Fastqc.html_r2]
    File qualimap_report = QualimapQc.archive
    File? target_scope_tsv = PrepareTargets.status_tsv
    File? target_in_scope_bed = PrepareTargets.in_scope_bed
    File? target_regions_all_sites_vcf = GenotypeTargetRegions.vcf
    File? target_regions_all_sites_index = GenotypeTargetRegions.index
    File? x_diploid_target_regions_all_sites_vcf = GenotypeXDiploidTargets.vcf
    File? x_diploid_target_regions_all_sites_index = GenotypeXDiploidTargets.index
    File? x_haploid_target_regions_all_sites_vcf = GenotypeXHaploidTargets.vcf
    File? x_haploid_target_regions_all_sites_index = GenotypeXHaploidTargets.index
    File? y_haploid_target_regions_all_sites_vcf = GenotypeYHaploidTargets.vcf
    File? y_haploid_target_regions_all_sites_index = GenotypeYHaploidTargets.index
    File? mt_target_regions_vcf = SelectMtTargetVariants.vcf
    File? mt_target_regions_index = SelectMtTargetVariants.index
  }
}
