from multiprocessing import cpu_count
full_core=cpu_count()

configfile: "config.yaml"

rule concat_reads:
    input:
        config["reads_folder"]
    output:
        temp(expand("{out_dir}/reads/all_reads.fastq.gz", out_dir=config["out_dir"]))
    message: "concatening the reads into one reads file"
    shell:
        "cat {input}/* > {output}"


rule QC_reads:
    input:
        rules.concat_reads.output
    output:
        expand("{out_dir}/QC/nanoplot/NanoPlot-report.html", out_dir=config["out_dir"])
    threads: 4
    log: expand("{out_dir}/logs/filtering_reads/nanofilt.log", out_dir=config["out_dir"])
    message: "QC of the filtering using nanoplot"
    conda:
        "env/nanoplot.yaml"
    params:
        folder=expand("{out_dir}/QC/nanoplot/", out_dir=config["out_dir"])
    shell:
        "( NanoPlot -t {threads} -o {params.folder} --fastq {input} ) 2> {log}"


rule assembly_hifiasm:
    input:
        rules.concat_reads.output
    output:
        gfa=expand("{out_dir}/assembly_hifiasm/{asm_name}.bp.p_ctg.gfa", out_dir=config["out_dir"], asm_name=config["asm_name"]),
        fa=expand("{out_dir}/assembly_hifiasm/{asm_name}.bp.p_ctg.fa", out_dir=config["out_dir"], asm_name=config["asm_name"])
    threads: full_core
    log: expand("{out_dir}/logs/assembly/hifiasm.log", out_dir=config["out_dir"])
    message: "Assembling the reads with hifiasm"
    conda:
        "env/hifiasm.yaml"
    params:
        name=config["asm_name"],
        outdir=expand("{out_dir}/assembly_hifiasm/",out_dir=config["out_dir"]),
        cmd1="'/^S/{print",
        cmd2='">"$2;print',
        cmd3="$3}'"
    shell:
        "cd {params.outdir} && (hifiasm -o {params.name} -t {threads} {input} && awk {params.cmd1} {params.cmd2} {params.cmd3} {output.gfa} > {output.fa} ) 2> {log}"


rule QC_assembly_quast:
    input:
        rules.assembly_hifiasm.output.fa
    output:
        expand("{out_dir}/QC/QUAST/DRAFT_ASSEMBLY/report.tsv", out_dir=config["out_dir"])
    threads: 4 
    log: expand("{out_dir}/logs/QC_QUAST/draft_assembly.log", out_dir=config["out_dir"])
    message: "Quality Control of the assembly using QUAST"
    params:
        out_dir=expand("{out_dir}/QC/QUAST/DRAFT_ASSEMBLY", out_dir=config["out_dir"])
    conda:
        "env/quast.yaml"
    shell:
        "(quast {input} -o {params.out_dir} -t {threads} --eukaryote --large) 2> {log}"


rule QC_assembly_busco:
    input:
        rules.assembly_hifiasm.output.fa
    output:
        expand("{out_dir}/QC/BUSCO/{asm_name}_DRAFT/logs/busco.log", out_dir=config["out_dir"],asm_name=config["asm_name"])
    threads: full_core
    message: "Quality Control of the assembly using BUSCO"
    params:
        out_dir=expand("{out_dir}/QC/BUSCO/", out_dir=config["out_dir"]),
        busco_name=expand("{asm_name}_DRAFT",asm_name=config["asm_name"]),
        db=config["busco_db"]
    log: expand("{out_dir}/logs/QC_BUSCO/draft_assembly.log", out_dir=config["out_dir"])
    conda:
        "env/busco.yaml"
    shell:
        "( busco -f -c {threads} -l {params.db} -m genome --out_path {params.out_dir} -i {input} -o {params.busco_name}) 2> {log}"

rule assembly:
    input:
        ba=rules.QC_assembly_busco.output,
        qa=rules.QC_assembly_quast.output,
        nr=rules.QC_reads.output