version 1.0

task PrepareCapture {
  input {
    File? capture_bed
    File ref_fai
    Int capture_padding
    String sex_chromosome_complement
    File script
    File validated
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
    stage_file "~{script}" intervals.py
    stage_file "~{ref_fai}" ref.fa.fai
    if [ -n '~{default="" capture_bed}' ]; then
      stage_file '~{default="" capture_bed}' capture.bed
      capture_arg=capture.bed
    else
      capture_arg=''
    fi
    test -s "$(input_path "~{validated}")"
    python3 intervals.py capture --fai ref.fa.fai --capture-bed "$capture_arg" \
      --padding ~{capture_padding} --calling-bed calling_intervals.bed \
      --excluded-tsv excluded_capture_intervals.tsv --summary-json capture_summary.json \
      --analysis-bed analysis_intervals.bed \
      --bqsr-bed bqsr_intervals.bed \
      --sex-chromosome-complement ~{sex_chromosome_complement} \
      --x-diploid-bed x_diploid.bed --has-x-diploid has_x_diploid.txt \
      --x-haploid-bed x_haploid.bed --has-x-haploid has_x_haploid.txt \
      --y-haploid-bed y_haploid.bed --has-y-haploid has_y_haploid.txt \
      --mt-bed mt.bed --has-mt has_mt.txt
    cp -f calling_intervals.bed excluded_capture_intervals.tsv capture_summary.json analysis_intervals.bed bqsr_intervals.bed x_diploid.bed has_x_diploid.txt x_haploid.bed has_x_haploid.txt y_haploid.bed has_y_haploid.txt mt.bed has_mt.txt "$call_dir"/
  >>>
  output {
    File calling_bed = "calling_intervals.bed"
    File analysis_bed = "analysis_intervals.bed"
    File bqsr_bed = "bqsr_intervals.bed"
    File x_diploid_bed = "x_diploid.bed"
    File x_haploid_bed = "x_haploid.bed"
    File y_haploid_bed = "y_haploid.bed"
    File mt_bed = "mt.bed"
    Boolean has_x_diploid = read_boolean("has_x_diploid.txt")
    Boolean has_x_haploid = read_boolean("has_x_haploid.txt")
    Boolean has_y_haploid = read_boolean("has_y_haploid.txt")
    Boolean has_mt = read_boolean("has_mt.txt")
    File excluded_tsv = "excluded_capture_intervals.tsv"
    File summary = "capture_summary.json"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
  }
}
