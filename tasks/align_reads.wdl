version 1.0

task AlignReads {
  input {
    File r1
    File r2
    String sample_id
    String library_id
    String platform
    File ref_fasta
    File ref_fai
    File ref_dict
    Array[File]+ bwa_index_files
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
    stage_file "~{ref_fasta}" ref.fa
    test -s "$(input_path "~{validated}")"
    for index in ~{sep=' ' bwa_index_files}; do
      extension="${index##*.}"
      stage_file "$index" "ref.fa.$extension"
    done
    for extension in amb ann bwt pac sa; do test -s "ref.fa.$extension"; done
    rg=$(printf '@RG\tID:%s\tSM:%s\tLB:%s\tPL:%s' \
      '~{sample_id}' '~{sample_id}' '~{library_id}' '~{platform}')
    bwa mem -M -t ~{threads} -R "$rg" ref.fa R1.fq.gz R2.fq.gz | \
      samtools sort -@ ~{threads} -T "$local_work/sorttmp" -o ~{sample_id}.sorted.bam -
    samtools index -@ ~{threads} ~{sample_id}.sorted.bam
    cp -f ~{sample_id}.sorted.bam ~{sample_id}.sorted.bam.bai "$call_dir"/
  >>>
  output {
    File bam = "${sample_id}.sorted.bam"
    File bai = "${sample_id}.sorted.bam.bai"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
