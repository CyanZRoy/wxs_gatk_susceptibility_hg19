version 1.0

task PrepareTargets {
  input {
    File target_bed
    File? capture_bed
    File calling_bed
    File x_diploid_bed
    File x_haploid_bed
    File y_haploid_bed
    File mt_bed
    String sex_chromosome_complement
    File ref_fai
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
    stage_file "~{script}" intervals.py
    stage_file "~{ref_fai}" ref.fa.fai
    stage_file "~{target_bed}" target.bed
    stage_file "~{calling_bed}" calling.bed
    stage_file "~{x_diploid_bed}" x_diploid.bed
    stage_file "~{x_haploid_bed}" x_haploid.bed
    stage_file "~{y_haploid_bed}" y_haploid.bed
    stage_file "~{mt_bed}" mt.bed
    if [ -n '~{default="" capture_bed}' ]; then
      stage_file '~{default="" capture_bed}' capture.bed
      capture_arg=capture.bed
    else
      capture_arg=''
    fi
    python3 intervals.py targets --fai ref.fa.fai --target-bed target.bed \
      --capture-bed "$capture_arg" --calling-bed calling.bed \
      --in-scope-bed target_in_scope.bed --status-tsv target_scope.tsv \
      --has-in-scope has_in_scope.txt \
      --sex-chromosome-complement ~{sex_chromosome_complement} \
      --x-diploid-bed x_diploid.bed --x-diploid-in-scope-bed x_diploid_target.bed --has-x-diploid has_x_diploid.txt \
      --x-haploid-bed x_haploid.bed --x-haploid-in-scope-bed x_haploid_target.bed --has-x-haploid has_x_haploid.txt \
      --y-haploid-bed y_haploid.bed --y-haploid-in-scope-bed y_haploid_target.bed --has-y-haploid has_y_haploid.txt \
      --mt-bed mt.bed --mt-in-scope-bed mt_target.bed --has-mt has_mt.txt
    cp -f target_in_scope.bed target_scope.tsv has_in_scope.txt x_diploid_target.bed has_x_diploid.txt x_haploid_target.bed has_x_haploid.txt y_haploid_target.bed has_y_haploid.txt mt_target.bed has_mt.txt "$call_dir"/
  >>>
  output {
    File in_scope_bed = "target_in_scope.bed"
    File status_tsv = "target_scope.tsv"
    Boolean has_in_scope = read_boolean("has_in_scope.txt")
    File x_diploid_in_scope_bed = "x_diploid_target.bed"
    File x_haploid_in_scope_bed = "x_haploid_target.bed"
    File y_haploid_in_scope_bed = "y_haploid_target.bed"
    File mt_in_scope_bed = "mt_target.bed"
    Boolean has_x_diploid = read_boolean("has_x_diploid.txt")
    Boolean has_x_haploid = read_boolean("has_x_haploid.txt")
    Boolean has_y_haploid = read_boolean("has_y_haploid.txt")
    Boolean has_mt = read_boolean("has_mt.txt")
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
  }
}
