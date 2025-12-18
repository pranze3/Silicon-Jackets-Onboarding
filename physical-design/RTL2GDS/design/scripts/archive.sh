date=$(date +"%m.%d.%y_%T")
dir=".logarchive/$date/"
mkdir -p $dir
echo "=> Purging archived logs older than 7 days ..."
find .logarchive -type d -mtime +7 -exec rm -rf {} +
echo "=> Moving flow outputs to .logarchive/$date/ ..."
mv *.cmd* \
*.metrics \
*.status \
*.rpt \
*.net \
*.bin \
*.tstamp \
*.log* \
*.bin \
logs/ \
reports/ \
flow.status.d/ \
flow.metrics.d/ \
debug/ \
client_log/ \
*_outputs \
fv/ \
dbs/ \
*lock* \
*.map \
*.gui \
*.option \
*output/ \
*scheduling* \
.inferred* \
*.tstamp* \
$dir \
2>/dev/null
echo "=> Archive complete"
