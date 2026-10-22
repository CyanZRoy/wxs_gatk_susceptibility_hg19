version 1.0

task Fastqc {
  input {
    File r1
    File r2
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
    stage_file "~{r1}" R1.fq.gz
    stage_file "~{r2}" R2.fq.gz
    mkdir reports
    fastqc -t ~{threads} -o reports R1.fq.gz R2.fq.gz
    mv reports/R1_fastqc.html ~{sample_id}.R1.fastqc.html
    mv reports/R2_fastqc.html ~{sample_id}.R2.fastqc.html
    cp -f ~{sample_id}.R1.fastqc.html ~{sample_id}.R2.fastqc.html "$call_dir"/
  >>>
  output {
    File html_r1 = "${sample_id}.R1.fastqc.html"
    File html_r2 = "${sample_id}.R2.fastqc.html"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 120"
  }
}
