#!/bin/bash

trap "kill 0" SIGINT
trap "kill -2 0" SIGTERM
INTERVAL=10
HISTORY_SIZE=360
CS=60
SOURCE=/run/dump1090-fa
source /etc/default/tar1090

dir=/run/tar1090
hist=$(($HISTORY_SIZE))
chunks=$(( $hist/$CS ))
partial=$(($hist%$CS))
if [[ $partial != 0 ]]
then actual_chunks=$(($chunks+2))
else actual_chunks=$(($chunks+1))
fi


while true
do
	cd $dir
	rm -f $dir/*.gz
	rm -f $dir/*.json

	if ! cp $SOURCE/receiver.json chunks.json
	then
		sleep 60
		continue
	fi
	if [[ $ENABLE_978 == "yes" ]]; then
		sed -i -e "s?history\" : [0-9]*?chunks\" : $actual_chunks, \"enable_uat\" : \"true\"?" chunks.json
	else
		sed -i -e "s/history\" : [0-9]*/chunks\" : $actual_chunks/" chunks.json
	fi

	i=0
	j=0

	sleep 2;

	while true
	do
		sleep $INTERVAL &


		cd $dir
		if ! cp $SOURCE/aircraft.json history_$((i%$CS)).json &>/dev/null
		then
			sleep 0.05
			cp $SOURCE/aircraft.json history_$((i%$CS)).json
		fi
		sed -i -e '$a,' history_$((i%$CS)).json

		if [[ $ENABLE_978 == "yes" ]]; then
			cp $dir/978.json $dir/978_history_$((i%$CS)).json
			sed -i -e 's/"now" \?:/"uat_978":"true","now":/' -e '$a,' 978_history_$((i%$CS)).json
		fi



		if [[ $((i%6)) == 5 ]]
		then
			sed -e '1i{ "files" : [' -e '$a]}' -e '$d' *history_*.json | gzip -1 > temp.gz
			mv temp.gz chunk_$j.gz
			rm -f *latest_*.json chunk_$(($actual_chunks - 1)).gz
		else
			cp history_$((i%$CS)).json latest_$((i%6)).json
			if [[ $ENABLE_978 == "yes" ]]; then
				cp 978_history_$((i%$CS)).json 978_latest_$((i%6)).json
			fi
			sed -e '1i{ "files" : [' -e '$a]}' -e '$d' *latest_*.json | gzip -1 > temp.gz
			mv temp.gz chunk_$(($actual_chunks - 1)).gz
		fi

		i=$((i+1))

		if [[ $i == $CS ]]
		then
			sed -e '1i{ "files" : [' -e '$a]}' -e '$d' *history_*.json | gzip -9 > temp.gz
			mv temp.gz chunk_$j.gz
			i=0
			j=$((j+1))
			rm -f *history_*.json
		fi
		if [[ $j == $chunks ]] && [[ $i == $partial ]]
		then
			sed -e '1i{ "files" : [' -e '$a]}' -e '$d' *history_*.json 2>/dev/null | gzip -9 > temp.gz
			mv temp.gz chunk_$j.gz 2>/dev/null
			i=0
			j=0
			rm -f *history_*.json
		fi

		wait
	done
	sleep 5
done &

while [[ $ENABLE_978 == "yes" ]]
do
	sleep 1 &
	wget -T 5 -q -O $dir/978.tmp $URL_978/data/aircraft.json
	mv $dir/978.tmp $dir/978.json
	wait
done &

wait

exit 0

