#!/bin/bash

config_file="$1"

if test -z "$config_file"
then
	echo "Syntax: snmp.sh <config>"
	exit
fi

if ! test -e "$config_file"
then
	echo "Warning: configuration file '$config_file' does not exist!"
	exit
fi

if ! test -s "$config_file"
then
	echo "Warning: configuration file '$config_file' is empty!"
	exit
fi

egrep -v '^\s*[#;]' "$config_file" | while read host community version port
do
	if test -z "$community"
	then
		community="public"
	fi

	if test -z "$version"
	then
		version="2c"
	fi

	if test -z "$port"
	then
		port="161"
	fi

	if test -n "$host"
	then
		temp="/tmp/snmp-$host-$port-$$"
		echo "Probing '$host' [community=$community, version=$version, port=$port] ..."
		rrd-client.pl -q -s "$host" -c "$community" -V "$version" -P "$port" > "$temp"
		cat "$temp" | rrd-server.pl -u "$host"
		rm -f "$temp"
	fi
done

