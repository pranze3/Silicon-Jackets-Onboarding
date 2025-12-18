.PHONY = clean archive purge

#This removes all report and result files, modify as needed here
clean:
	-@ rm -rf *.cmd* \
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
				*scheduling* \
				.inferred* \
				*.tstamp* \
				*output/

#This relocates all report and result files into .logarchive/{date} and purges archived logs >7 days old.
archive:
	-@ ./scripts/archive.sh

#This purges all archives reports
purge:
	-@ rm -rf .logarchive
