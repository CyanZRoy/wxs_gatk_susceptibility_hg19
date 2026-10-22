version 1.0

task QualimapQc {
  input {
    File bam
    File bai
    File? capture_bed
    String sample_id
    String docker_image
    String cluster_config
    Int threads
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
    stage_file "~{bam}" input.bam
    stage_file "~{bai}" input.bam.bai
    if [ -n '~{default="" capture_bed}' ]; then
      stage_file '~{default="" capture_bed}' capture.bed
    fi
    if [ -n '~{default="" capture_bed}' ]; then
      awk 'BEGIN{OFS="\t"} !/^#/ && NF>=3 {print $1,$2,$3,".",0,"."}' capture.bed > capture.gff.bed
      qualimap bamqc -bam input.bam -gff capture.gff.bed -nt ~{threads} \
        --java-mem-size=24G -outformat PDF:HTML -outdir report
    else
      qualimap bamqc -bam input.bam -nt ~{threads} \
        --java-mem-size=24G -outformat PDF:HTML -outdir report
    fi
    tar -czf ~{sample_id}.qualimap.tar.gz report
    cp -f ~{sample_id}.qualimap.tar.gz "$call_dir"/
  >>>
  output { File archive = "${sample_id}.qualimap.tar.gz" }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
