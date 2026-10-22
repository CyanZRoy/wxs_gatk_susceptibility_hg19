version 1.0

task MarkDuplicates {
  input {
    File input_bam
    File input_bai
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
    gatk --java-options '-Xmx24g' MarkDuplicatesSpark \
      -I input.bam -O ~{sample_id}.dedup.bam -M ~{sample_id}.duplicates.txt
    samtools index ~{sample_id}.dedup.bam
    cp -f ~{sample_id}.dedup.bam ~{sample_id}.dedup.bam.bai ~{sample_id}.duplicates.txt "$call_dir"/
  >>>
  output {
    File bam = "${sample_id}.dedup.bam"
    File bai = "${sample_id}.dedup.bam.bai"
    File metrics = "${sample_id}.duplicates.txt"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
