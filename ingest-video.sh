#!/bin/bash
#
# ingest-video.sh
#
# Copyright (c) 2015 Tobias Haeberle
#

about() {
    cat <<EOF
$program 1.0 of January 11, 2015
Copyright (c) 2015 Tobias Haeberle
EOF
    exit 0
}

usage() {
    cat <<EOF
Ingest video.

Usage: $program [OPTION]... [FILE]

    --help      display this help and exit
    --version   output version information and exit
    --destination PATH
    			Move qualified files into this directory.

Requires \`mkvmerge\` and \`mp4info\` executables in \$PATH
EOF
    exit 0
}

syntax_error() {
    echo "$program: $1" >&2
    echo "Try \`$program --help\` for more information." >&2
    exit 1
}

die() {
    echo "$program: $1" >&2
    exit ${2:-1}
}

readonly program="$(basename "$0")"

case $1 in
    --help)
        usage
        ;;
    --version)
        about
        ;;
esac

dest_dir='.'
send_to_itunes=''

while [ "$1" ]; do
    case $1 in
        --destination)
			if [ ! -d "$2" ]; then
				die "Destination directory not found: $2"
			fi

			dest_dir="$2"
			shift
		;;
		--itunes)
			send_to_itunes='yes'
		;;
		-*)
            syntax_error "unrecognized option: $1"
            ;;
        *)
            break
            ;;
    esac
    shift
done

readonly input="$1"

if [ ! "$input" ]; then
    syntax_error 'too few arguments'
fi

if [ ! -f "$input" ]; then
    die "input file not found: $input"
fi

for tool in mkvmerge mp4info; do

    if ! $(which $tool >/dev/null); then
        die "executable not in \$PATH: $tool"
    fi
done

readonly identification="$(mkvmerge --identify-verbose "$input")"
readonly input_container="$(echo "$identification" | sed -n 's/^File .*: container: \(.*\) \[.*\]$/\1/p')"

if [ ! "$input_container" ]; then
    die "unknown input container format: $input"
fi

if [  "$input_container" != 'QuickTime/MP4' ]; then
	die "unsupported input container format: $input_container"
fi

mp4info="$(mp4info "$input")"

name="$(echo "$mp4info" | sed -n 's/^ Name: \(.*\)$/\1/p')"

if [ ! "$name" ]; then
	die "Name not found: $input"
fi

release_year="$(mp4info "$input" | grep 'Release Date' | sed -n 's/.*Release Date: \([0-9]\{4\}\)-.*-.*/\1/p')"

if [ ! "$release_year" ]; then
	die "Release year not found: $input"
fi

size_array=($(echo "$mp4info" | sed -n "s/^1.*video.*, \([0-9]\{1,\}\)x\([0-9]\{1,\}\).*$/\1 \2/p"))

if ((${#size_array[*]} != 2)); then
    die "video size not found: $input"
fi

width="${size_array[0]}"
height="${size_array[1]}"

quality=''

if (($width > 1920)) || (($height > 1080)); then
    quality='4K'

elif (($width > 1280)) || (($height > 720)); then
    quality='1080p HD'

elif (($width > 720)) || (($height > 576)); then
    quality='720p HD'
else
    quality='SD'
fi


# strip :, \, /
name=${name//[:\/\\]}

directory_name="$name ($release_year)"
filename="$directory_name - $quality.m4v"

directory_path="$dest_dir/$directory_name"
file_path="$directory_path/$filename"

if [ ! -d "$directory_path" ]; then
	mkdir "$directory_path"
	if [ $? -gt 0 ]; then
		die "Could not create directory: $directory_path"
	fi
fi

if [ -f "$file_path" ]; then
	die "File already exists: $file_path"
fi

mv "$input" "$file_path"
if [ $? -gt 0 ]; then
	die "Failed to move file: $input"
fi

if [ "$send_to_itunes" == 'yes' ]; then

	abs_path="$file_path"
	if [[ "$abs_path" =~ "^/.*" ]]; then
		abs_path="$file_path"
	else
		abs_path="$(pwd)/${file_path#./}"
	fi 

	osascript <<EOF
set p to "$abs_path"
set a to POSIX file p

tell application "iTunes"
	add a
end tell
EOF
fi

