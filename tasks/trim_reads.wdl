version 1.0

task TrimReads {
  input {
    File r1
    File r2
    String sample_id
    File validated
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
    stage_file "~{r1}" R1.fq.gz
    stage_file "~{r2}" R2.fq.gz
    test -s "$(input_path "~{validated}")"
    fastp --thread ~{threads} -i R1.fq.gz -I R2.fq.gz \
      -o ~{sample_id}.R1.trimmed.fq.gz -O ~{sample_id}.R2.trimmed.fq.gz \
      -j ~{sample_id}.fastp.json -h ~{sample_id}.fastp.html
    cp -f ~{sample_id}.R1.trimmed.fq.gz ~{sample_id}.R2.trimmed.fq.gz ~{sample_id}.fastp.json ~{sample_id}.fastp.html "$call_dir"/
  >>>
  output {
    File trimmed_r1 = "${sample_id}.R1.trimmed.fq.gz"
    File trimmed_r2 = "${sample_id}.R2.trimmed.fq.gz"
    File report_json = "${sample_id}.fastp.json"
    File report_html = "${sample_id}.fastp.html"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 200"
  }
}
