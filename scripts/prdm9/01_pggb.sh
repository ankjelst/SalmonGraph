#!/bin/bash

#SBATCH --ntasks=8
#SBATCH --nodes=1                # Use 1 node
#SBATCH --job-name=pggb  # sensible name for the job
#SBATCH --mem=150G                 # Default memory per CPU is 3GB.
#SBATCH --output=log-pggb-%j.out
#SBATCH --constraint="avx2" # IMPOTATANT!!! PGGB jobs will fail without this
#SBATCH --partition=hugemem

set -o errexit # exit on errors
set -o nounset # treat unset variables as errors


echo "START"
date

#INPUT : full path to one fasta file
# NB! if you include more graphics with for instance --multiqc, --layout and --stats you should ask for more memory 
# NB2! if you are running this script with a full chromosome input you should ask for a lot more memory


######
## Parameters

fasta=/mnt/SCRATCH/ankjelst/data/prdm9/prdm9-znf.fasta
haplotypes=$(cat $fasta | grep "^>" | cut -d "#" -f 1,2 | uniq | wc -l)

#wfmash
param_s=5000 # segment size, this should only be this small because we have a small graph, for full chromosomes set larger
param_p=98 # percent identity in the wfmash step, including variants. This should not be so strict for this small example
param_n=$haplotypes  #Ideally, you should set this to equal the number of haplotypes in the pangenome.
param_i="$(basename $fasta)" 


#seqwish
param_k=$1 #filter exact matches below this length [default: 29]

#smoothxg
param_H=$haplotypes # number of haplotypes, if different than that set with -n
param_G="7919,8069" # target sequence length for POA, first pass = N, second pass = M [default: 13117,13219]
param_P="1,19,39,3,81,1" # default and fits 98 % identity sequences
#param_P="1,4,6,2,26,1" # for p = 95

#deconstruct
#param_V=ssa05:sample.list  
#OBSOBS the reference for the vcf here
#specify a set of VCFs to produce with SPEC = [REF:SAMPLE_LIST_FILE] the paths matching ^REF are used as a reference
param_V='SimonResolved#'

SCRATCHout=/mnt/SCRATCH/ankjelst/data/prdm9/pggb-final-k"$param_k"-p"$param_p".out

out=pggb-$(basename $fasta)-k"$param_k".out

##########
# Copy input files to tmpdir

mkdir -p $TMPDIR/$USER/$SLURM_JOBID #Not all nodes my TMP dir exist

cd $TMPDIR/$USER/$SLURM_JOBID

cp -v "$fasta" .

echo "i:"$param_i""

####
# Running pggb

echo "RUN PGGB"

singularity exec /mnt/users/ankjelst/tools/pggb_v0.2.0.sif pggb -i $param_i -s $param_s -p $param_p \
-Y '#' -v -n $param_n -t $SLURM_CPUS_ON_NODE -k $param_k -o $out -G $param_G -P $param_P -H $param_H 


#####
# Vis of prm9 region

odgi=$(ls $out/*.smooth.og)
fastabase=$(basename "$fasta")

singularity exec /mnt/users/ankjelst/tools/pggb_v0.2.0.sif odgi viz -i "$odgi" -o znf.png -x 500 -s"#" -r "SimonResolved#2#znfArray:0-10671"

echo "CHOP GFA"

# vg does not like nodes >1024 bp. We chop the graph ourselves to avoid coordinate inconsistency between mapped file and graph.


singularity exec /mnt/users/ankjelst/tools/pggb_v0.2.0.sif odgi chop -c 1024 -i $odgi -o "$fastabase"-chop.og

singularity exec /mnt/users/ankjelst/tools/pggb_v0.2.0.sif odgi view -i "$fastabase"-chop.og --to-gfa > "$fastabase"-chop.gfa


singularity exec /mnt/users/ankjelst/tools/vg_v1.38.0.sif vg deconstruct -p "SimonResolved#2#znfArray" -H "#" -e "$fastabase"-chop.gfa > "$fastabase"-chop.vcf


echo "MOVE FILES TO SCRATCH"

mkdir -p $SCRATCHout

mv -v "$fastabase"-chop.gfa "$fastabase"-chop.vcf "$odgi"  znf.png "$out"/*.png $SCRATCHout

cd ..

echo "DELETE TMP-FILES"

ls $TMPDIR/$USER

rm -r $TMPDIR/$USER/$SLURM_JOBID

echo "AFTER deleting"

ls $TMPDIR/$USER/

echo "FINISHED"

date
