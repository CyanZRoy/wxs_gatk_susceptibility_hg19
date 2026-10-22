version 1.0

task SelectMtTargetVariants {
  input {
    File input_vcf
    File input_index
    File ref_fasta
    File ref_fai
    File ref_dict
    File in_scope_bed
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
    stage_file "~{input_vcf}" input.vcf.gz
    stage_file "~{input_index}" input.vcf.gz.tbi
    stage_file "~{ref_fasta}" ref.fa
    stage_file "~{ref_fai}" ref.fa.fai
    stage_file "~{ref_dict}" ref.dict
    stage_file "~{in_scope_bed}" in_scope.bed
    gatk --java-options '-Xmx24g' SelectVariants \
      -R ref.fa -V input.vcf.gz -L in_scope.bed \
      -O ~{sample_id}.mt.target_regions.vcf.gz
    if [ ! -s ~{sample_id}.mt.target_regions.vcf.gz.tbi ]; then
      gatk IndexFeatureFile -I ~{sample_id}.mt.target_regions.vcf.gz
    fi
    test -s ~{sample_id}.mt.target_regions.vcf.gz.tbi
    cp -f ~{sample_id}.mt.target_regions.vcf.gz ~{sample_id}.mt.target_regions.vcf.gz.tbi "$call_dir"/
  >>>
  output {
    File vcf = "${sample_id}.mt.target_regions.vcf.gz"
    File index = "${sample_id}.mt.target_regions.vcf.gz.tbi"
  }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 150"
  }
}
