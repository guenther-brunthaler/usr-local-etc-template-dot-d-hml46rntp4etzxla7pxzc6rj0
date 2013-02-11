#! /bin/sh
# Create files documenting the current system configuration, especially
# partition layout and hardware configuration.
#
# The generated files as well as the configuration file for this script are
# intended to be kept under version control. This allows to detect changes to
# those configuration details later on.
#
# (c) 2011 - 2013 by Guenther Brunthaler.
# This script is free software.
# Distribution is permitted under the terms of the GPLv3.


# LVM2 config file location (optional if LVM is not in use).
LVM2_CONF=/etc/lvm/lvm.conf


die() {
	echo "ERROR: $*" >& 2
	false; exit
}


run() {
	"$@" && return
	die "Command >>>$*<<< failed with return code ${?}!"
}


getcmd() {
	case $1 in
		-f) ;;
		*) set -- -- "$@"
	esac
	# There is a bug in bash's eval: It does not return the status of a
	# backquote substitution. Adding a redundant test to fix it.
	eval "$2=`which \"$3\" 2> /dev/null`; test $? = 0" && return
	test x"$1" = x"-f" || return
	die "Required utility '$3' is not installed!"
}


print_lvm2_backup_dir() {
	expand "$LVM2_CONF" \
	| sed -e '
		s/^ *//
		s/^#.*//
		/^$/ d
	' | "$AWK" '
		BEGIN {i= 0}
		$2 == "{" {ns[i++]= $1}
		$1 == "}" {--i}
		/=/ {
			split($0, t, " *= *")
			if ( \
				i == 1 && ns[0] == "backup" \
				&& t[1] == "backup_dir" \
			) {
				v= t[2]
				if (match(v, "\"") > 0) {
					v= substr(v, RSTART + RLENGTH)
					if (match(v, "\" *$") > 0) {
						v= substr(v, 1, RSTART - 1)
					}
				}
				print v
			}
		}
	'
}


LC_ALL=C
export LC_ALL
getcmd -f AWK awk
if getcmd FDISK fdisk && getcmd SFDISK sfdisk
then
	for DEV in /sys/block/*
	do
		DEV=${DEV##*/}
		case $DEV in
			loop[0-9]* | dm-* ) continue
		esac
		test -e /dev/"$DEV" || continue
		echo "Examining /dev/$DEV..." >& 2
		run test -b /dev/"$DEV"
		run "$FDISK" -lu /dev/"$DEV" | "$AWK" '
			/[^ ]/ {print}
			/dentifier:/ {exit}
		' > disk-id_"$DEV"_info.txt
		run "$SFDISK" -d /dev/"$DEV" > sfdisk_"$DEV"_backup.txt
	done
else
	echo "fdisk or sfdisk is missing," \
		"skipping partition table backups." >& 2
fi
if getcmd LSHW lshw
then
	"$LSHW" > lshw.txt
else
	echo "lshw is not installed; skipping." >& 2
fi
if ! getcmd BZR bzr || test ! -d /etc/.bzr
then
	BZR=
fi
if
	test -f "$LVM2_CONF" \
	&& { getcmd LVM lvm2 || getcmd LVM lvm; } \
	&& LVM2_BACKUP_DIR=`print_lvm2_backup_dir` \
	&& test -n "$LVM2_BACKUP_DIR" && test -d "$LVM2_BACKUP_DIR"
then
	"$LVM" vgdisplay | grep "VG Name" | "$AWK" '{print $NF}' |
	while read vg
	do
		if test -n "$BZR"
		then
			s=`
				"$BZR" st --short -- "$LVM2_BACKUP_DIR"/"$vg"
			` || s=X
			case $s in
				X* | "?"*) ;; # Unknown or ignored.
				*) continue # Version controlled; skip it.
			esac
		fi
		"$LVM" vgcfgbackup -f "$vg.lvm" "$vg"
	done
fi
