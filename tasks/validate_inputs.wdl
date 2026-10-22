version 1.0

task ValidateInputs {
  input {
    File identity_lines
    File fastq_r1
    File fastq_r2
    Array[File]+ bwa_index_files
    Int capture_padding
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
    stage_file "~{identity_lines}" identity_lines.txt
    test -s "$(input_path "~{fastq_r1}")"
    test -s "$(input_path "~{fastq_r2}")"
    test ~{length(bwa_index_files)} -eq 5
    test ~{capture_padding} -ge 0
    python3 -c 'import pathlib,re,sys; v=pathlib.Path(sys.argv[1]).read_text().splitlines(); assert len(v)==3, "identity field count"; assert all(re.fullmatch(r"[A-Za-z0-9_.-]+",x) for x in v)' identity_lines.txt
    printf 'ok\n' > validated.txt
    cp -f validated.txt "$call_dir"/
  >>>
  output { File marker = "validated.txt" }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
  }
}
