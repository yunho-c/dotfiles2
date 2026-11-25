function sscrop --description 'Crop a window screenshot and encode a black-backed 4:4:4 JPEG with jpegli'
    argparse h/help 'q/quality=' -- $argv; or return 2
    set -l usage 'Usage: sscrop [-q 1..100] INPUT.png [OUTPUT.jpg]'
    if set -q _flag_help
        echo "$usage"
        echo 'Defaults to jpegli quality 96, 4:4:4, and black corners. Saves beside the input.'
        return 0
    end
    if test (count $argv) -lt 1; or test (count $argv) -gt 2
        echo "$usage" >&2
        return 2
    end
    set -q _flag_quality; or set -l _flag_quality 96
    if not string match -qr '^(100|[1-9][0-9]?)$' -- "$_flag_quality"
        echo 'sscrop: quality must be an integer from 1 to 100' >&2
        return 2
    end

    set -l input (path resolve -- "$argv[1]")
    if not test -f "$input"
        echo "sscrop: could not find $argv[1]" >&2
        return 1
    end
    set -l output "$argv[2]"
    if not set -q argv[2]
        set output (path change-extension '' -- "$argv[1]")' (cropped).jpg'
    end
    if test -e "$output"; or test -L "$output"
        echo "sscrop: output already exists: $output" >&2
        return 1
    end
    set -l encoder (command -s cjpegli)
    if test -z "$encoder"
        set encoder "$HOME/.local/bin/cjpegli"
    end
    if not test -x "$encoder"
        echo 'sscrop: cjpegli is required' >&2
        return 1
    end

    # A one-pixel black border also gives fully opaque screenshots a valid trim.
    set -l bounds (command magick "png:$input" +repage -alpha set -alpha extract -threshold 90% \
        -bordercolor black -border 1 -trim -format '%wx%h+%[fx:page.x-1]+%[fx:page.y-1]' info:)
    or return 1
    if not string match -qr '^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$' -- "$bounds"
        echo 'sscrop: no pixels above 90% opacity' >&2
        return 1
    end

    set -l temp (command mktemp -- (path dirname -- "$output")/.sscrop.XXXXXXXX)
    or return 1
    command magick "png:$input" +repage -crop "$bounds" +repage -background black -alpha remove -alpha off \
        -define png:color-type=2 -define png:compression-level=1 png:- \
        | "$encoder" - "$temp" -q "$_flag_quality" --chroma_subsampling 444 --quiet
    set -l pipeline_status $pipestatus
    if test "$pipeline_status[1]" -ne 0; or test "$pipeline_status[2]" -ne 0
        command rm -- "$temp"
        return 1
    end

    # Publish only the finished JPEG. A concurrent export cannot overwrite it.
    command ln -- "$temp" "$output"
    set -l result $status
    command rm -- "$temp"
    test $result -eq 0; or return 1
    echo "$output"
end
