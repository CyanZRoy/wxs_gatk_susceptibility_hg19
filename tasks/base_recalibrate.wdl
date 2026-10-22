version 1.0

task BaseRecalibrate {
  input {
    File bam
    File bai
    File ref_fasta
    File ref_fai
    File ref_dict
    File dbsnp_vcf
    File dbsnp_index
    File mills_vcf
    File mills_index
    File calling_bed
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
    stage_file "~{bam}" input.bam
    stage_file "~{bai}" input.bam.bai
    stage_file "~{ref_fasta}" ref.fa
    stage_file "~{ref_fai}" ref.fa.fai
    stage_file "~{ref_dict}" ref.dict
    stage_file "~{dbsnp_vcf}" dbsnp.vcf
    stage_file "~{dbsnp_index}" dbsnp.vcf.idx
    stage_file "~{mills_vcf}" mills.vcf
    stage_file "~{mills_index}" mills.vcf.idx
    stage_file "~{calling_bed}" calling.bed
    gatk --java-options '-Xmx24g' BaseRecalibrator \
      -R ref.fa -I input.bam --known-sites dbsnp.vcf --known-sites mills.vcf \
      -L calling.bed -O ~{sample_id}.recal.table
    cp -f ~{sample_id}.recal.table "$call_dir"/
  >>>
  output { File table = "${sample_id}.recal.table" }
  runtime {
    docker: docker_image
    instanceTypes: [cluster_config]
    systemDisk: "cloud 500"
  }
}
