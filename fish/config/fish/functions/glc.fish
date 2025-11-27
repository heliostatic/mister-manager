function glc -d "Show last n commits ordered by changes"
	set -l last_n
	if test -n "$argv[1]"
		set last_n $argv[1]
	else
		set last_n 10
	end
	git log -n $last_n --numstat --pretty=format:"---%h - %ar - %an - %s" \
	| awk \
		'BEGIN { lines = 0 } /^---/ { if (lines > 0) { split(log_line, parts, " - ");\
	 	printf "%-10d %-25s %-20s %-14s %s\n", lines, parts[3], parts[2], substr(log_line, 4, 7), parts[4] }\
		log_line = $0; lines = 0 } /^[0-9]+[[:blank:]]+[0-9]+/ { lines += $1 + $2 }'\
	| sort -rn
end
