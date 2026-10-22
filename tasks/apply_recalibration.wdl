version 1.0

task ApplyRecalibration {
  input {
    File input_bam
    File input_bai
    File table
    File ref_fasta
    File ref_fai
    File ref_dict
    String sample_id
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
    stage_file "~{input_bam}" input.bam
    stage_file "~{input_bai}" input.bam.bai
    stage_file "~{table}" recal.table
    stage_file "~{ref_fasta}" ref.fa
    stage_file "~{ref_fai}" ref.fa.fai
    stage_file "~{ref_dict}" ref.dict
    gatk --java-options '-Xmx24g' ApplyBQSR \
      -R ref.fa -I input.bam --bqsr-recal-file recal.table \
      -O ~{sample_id}.recal.bam
    samtools index ~{sample_id}.recal.bam
    cp -f ~{sample_id}.recal.bam ~{sample_id}.recal.bam.bai "$call_dir"/
  >>>
  output {
    File bam = "${sample_id}.recal.bam"
    File bai = "${sample_id}.recal.bam.bai"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
