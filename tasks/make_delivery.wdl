version 1.0

task MakeDelivery {
  input {
    File gvcf
    File index
    File calling_bed
    File analysis_bed
    File? capture_bed
    File capture_summary
    File? target_bed
    String sex_chromosome_complement
    File? x_diploid_gvcf
    File? x_diploid_index
    File? x_haploid_gvcf
    File? x_haploid_index
    File? y_haploid_gvcf
    File? y_haploid_index
    File? mt_vcf
    File? mt_index
    File fastp_json
    File duplicate_metrics
    String sample_id
    File script
    String docker_image
    String cluster_config
  }
  command <<<
    set -euo pipefail
    call_dir="$PWD"
    input_path() {
      case "$1" in
        /*) printf '%s\n' "$1" ;;
        *) printf '%s/%s\n' "$call_dir" "$1" ;;
      esac
    }
    stage_file() {
      cp -f "$(input_path "$1")" "$2"
    }
    copy_task_logs() {
      for log in script stdout stderr; do
        if [ -f "$call_dir/$log" ]; then
          cp -f "$call_dir/$log" "$call_dir/$log.txt" || true
        fi
      done
    }
    trap copy_task_logs EXIT
    local_work=$(mktemp -d /tmp/wxs-task-XXXXXX)
    mkdir -p "$local_work/tmp"
    export TMPDIR="$local_work/tmp" TMP="$local_work/tmp" TEMP="$local_work/tmp"
    export _JAVA_OPTIONS="-Djava.io.tmpdir=$TMPDIR"
    cd "$local_work"
    stage_file "~{script}" delivery.py
    stage_file "~{gvcf}" input.g.vcf.gz
    stage_file "~{index}" input.g.vcf.gz.tbi
    stage_file "~{calling_bed}" calling.bed
    stage_file "~{analysis_bed}" analysis.bed
    stage_file "~{capture_summary}" capture_summary.json
    stage_file "~{duplicate_metrics}" duplicates.txt
    stage_file "~{fastp_json}" fastp.json
    if [ -n '~{default="" capture_bed}' ]; then stage_file '~{default="" capture_bed}' capture.bed; capture_arg=capture.bed; else capture_arg=''; fi
    if [ -n '~{default="" target_bed}' ]; then stage_file '~{default="" target_bed}' target.bed; target_arg=target.bed; else target_arg=''; fi
    if [ -n '~{default="" x_diploid_gvcf}' ]; then stage_file '~{default="" x_diploid_gvcf}' x_diploid.g.vcf.gz; x_diploid_arg=x_diploid.g.vcf.gz; else x_diploid_arg=''; fi
    if [ -n '~{default="" x_diploid_index}' ]; then stage_file '~{default="" x_diploid_index}' x_diploid.g.vcf.gz.tbi; x_diploid_index_arg=x_diploid.g.vcf.gz.tbi; else x_diploid_index_arg=''; fi
    if [ -n '~{default="" x_haploid_gvcf}' ]; then stage_file '~{default="" x_haploid_gvcf}' x_haploid.g.vcf.gz; x_haploid_arg=x_haploid.g.vcf.gz; else x_haploid_arg=''; fi
    if [ -n '~{default="" x_haploid_index}' ]; then stage_file '~{default="" x_haploid_index}' x_haploid.g.vcf.gz.tbi; x_haploid_index_arg=x_haploid.g.vcf.gz.tbi; else x_haploid_index_arg=''; fi
    if [ -n '~{default="" y_haploid_gvcf}' ]; then stage_file '~{default="" y_haploid_gvcf}' y_haploid.g.vcf.gz; y_haploid_arg=y_haploid.g.vcf.gz; else y_haploid_arg=''; fi
    if [ -n '~{default="" y_haploid_index}' ]; then stage_file '~{default="" y_haploid_index}' y_haploid.g.vcf.gz.tbi; y_haploid_index_arg=y_haploid.g.vcf.gz.tbi; else y_haploid_index_arg=''; fi
    if [ -n '~{default="" mt_vcf}' ]; then stage_file '~{default="" mt_vcf}' mt.vcf.gz; mt_arg=mt.vcf.gz; else mt_arg=''; fi
    if [ -n '~{default="" mt_index}' ]; then stage_file '~{default="" mt_index}' mt.vcf.gz.tbi; mt_index_arg=mt.vcf.gz.tbi; else mt_index_arg=''; fi
    python3 delivery.py --sample-id '~{sample_id}' --gvcf input.g.vcf.gz \
      --index input.g.vcf.gz.tbi --calling-bed calling.bed \
      --analysis-bed analysis.bed \
      --capture-bed "$capture_arg" --capture-summary capture_summary.json \
      --target-bed "$target_arg" \
      --sex-chromosome-complement ~{sex_chromosome_complement} \
      --x-diploid-gvcf "$x_diploid_arg" --x-diploid-index "$x_diploid_index_arg" \
      --x-haploid-gvcf "$x_haploid_arg" --x-haploid-index "$x_haploid_index_arg" \
      --y-haploid-gvcf "$y_haploid_arg" --y-haploid-index "$y_haploid_index_arg" \
      --mt-vcf "$mt_arg" --mt-index "$mt_index_arg" \
      --duplicate-metrics duplicates.txt \
      --fastp-json fastp.json \
      --qc-json ~{sample_id}.qc.json --manifest-json ~{sample_id}.run_manifest.json
    cp -f ~{sample_id}.qc.json ~{sample_id}.run_manifest.json "$call_dir"/
  >>>
  output {
    File qc_json = "${sample_id}.qc.json"
    File manifest_json = "${sample_id}.run_manifest.json"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 150"
  }
}
