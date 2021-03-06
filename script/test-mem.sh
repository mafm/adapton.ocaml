#!/bin/bash

[ $# -eq 1 ] || \
    (echo "Usage: ./test-mem.sh spareTrie.{{p,}.native,.byte}" &&\
     exit 1)

BINARY=$1
FREEMEM=$(free -k | grep Mem: | awk -F"[ ]+" '{print $7}')
MAXTIME=600
TIME=$(date +"%Y.%m.%d-%H.%M.%S")
OUTDIR="out/mem"
OUTFILE="$OUTDIR/$TIME"
CSVFILE="$OUTDIR/$TIME.csv"
HEADER="size,type,min_depth,art_ifreq,time,space"

[ -d $OUTDIR ] || mkdir -p $OUTDIR
echo "$HEADER" >> "$CSVFILE"

REPS="5"
MINDEPTHS="1 2 4 8 16"
ARTIFREQS="f0 f1 f2 f4 f8 d2,1 d2,2 d3,1 d3,2 1 2 4 8"
TYPES="ocaml-set trie-set ntrie-set"
SIZES="100 1000 10000 100000"
CMD=""
RES=""

for  i in `seq 1 $REPS`; do
for ty in $TYPES; do
for md in `[[ $ty == *trie-* ]] && echo $MINDEPTHS || echo -1`; do
for af in `[[ $ty == ntrie-* ]] && echo $ARTIFREQS || echo -1`; do
for sz in $SIZES; do
    read -r -d '' CMD << EOM
ulimit -t $MAXTIME -v $FREEMEM ; \
/usr/bin/time -v \
sh -c "./$BINARY -size $sz -type $ty -min-depth $md -art-ifreq $af -verbose" |& \
tee -a $OUTFILE
EOM
    echo $CMD | tee -a $OUTFILE
    RES=`bash -c "$CMD"`
    echo "$RES"
    MEMUSE=`echo "$RES" | grep 'Maximum resident' | awk -F" " '{print $6}'`
    TIMEUSE=`echo "$RES" | grep 'User time' | awk -F" " '{print $4}'`
    echo "MEMUSE  = $MEMUSE"
    echo "TIMEUSE = $TIMEUSE"
    csvmd=`[ "$md" == "-1" ] && echo NA || echo $md`
    csvaf=`[ "$af" == "-1" ] && echo NA || echo $af`
    echo "$sz,$ty,$csvmd,$csvaf,$TIMEUSE,$MEMUSE" >> "$CSVFILE"
    echo
done
done
done
done
done
