#! /usr/bin/env tcsh

# get rdb tools
source /proj/axaf/simul/etc/mst_envs.tcsh

cat << HTR >! dhheater_history.hdr
time	command
S	S
HTR

cat << HTR2 >! dhheater_history2.hdr
command	time
S	S
HTR2

cat << TZERO >! tzero.rdb
command	time
S	S
1HHTRBON	1999:001:00:00:00.000
1HHTRBOF	2008:098:21:41:00.000
1HHTRBON	2014:259:02:13:00.000
TZERO

cat << TLAST >! tlast.rdb
command	time
S	S
1HHTRBON	2098:001:00:00:00.000
1HHTRBON	2098:001:00:00:01.000
TLAST

grep 1HHTRBO /data/acis/LoadReviews/20*/*/ofls/ACIS-LoadReview.txt \
| grep -v ERROR \
| grep -v TEST \
| sed 's|^/.*.txt:||' \
| awk '{print $1,"	",$4}' \
| sed 's/ //g' \
| cat dhheater_history.hdr - \
| sorttbl -uniq time \
| column command time \
| rdbcat tzero.rdb - \
| sorttbl -uniq time \
>! dhheater_history.rdb



cat < dhheater_history.rdb \
| column command time | headchg -del \
| sed 's/[0-8]$/9/' \
| sed 's/799$/800/' \
| cat dhheater_history2.hdr - \
| rdbcat dhheater_history.rdb - | sorttbl time \
| rdbcat tzero.rdb - tlast.rdb \
| tee ht.tmp \
| row time gt 1999:000:00:00:00.000 \
>! ht2.tmp


cat ht.tmp \
| column -v -a rownum N \
| compute rownum = _NR \
| tee tmp_ht1.tmp \
| compute rownum -= 1 \
| row rownum gt 0 \
>! tmp_ht2.tmp

set max=`rdbstats rownum < tmp_ht1.tmp | column rownum_max| headchg -del`
cat tmp_ht1.tmp \
| row rownum lt $max \
| column rownum -c command old_command -c time old_time \
| jointbl rownum tmp_ht2.tmp \
| column -v -a dahtbon N \
| compute dahtbon = 0 if command eq 1HHTRBON and old_command eq 1HHTRBOF \
| compute dahtbon = 1 if command eq 1HHTRBON and old_command eq 1HHTRBON \
| compute dahtbon = 1 if command eq 1HHTRBOF and old_command eq 1HHTRBON \
| compute dahtbon = 0 if command eq 1HHTRBOF and old_command eq 1HHTRBOF \
| tee test.rdb \
| column time dahtbon \
>! dahtbon_history.rdb

rm -f test.rdb tmp_ht[12].tmp ht2.tmp ht.tmp dhheater_history.hdr tlast.rdb
rm -f dhheater_history.rdb dhheater_history2.hdr tzero.rdb

