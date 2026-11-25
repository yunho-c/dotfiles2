function sscrop --description 'Crop PNG screenshots and save black-backed JPEGs with jpegli'
    argparse h/help 'q/quality=' -- $argv; or return 2
    set -l usage 'Usage: sscrop [-q high|mid|1..100] INPUT.png [INPUT.png ...]' \
        '       sscrop [-q high|mid|1..100] INPUT.png OUTPUT.jpg'
    if set -q _flag_help
        printf '%s\n' $usage
        echo 'high (default) uses Q96 at 4:4:4. mid uses Q70 at 4:2:0. Numeric qualities use 4:4:4.'
        echo 'Saves each screenshot as "<name> (cropped).jpg".'
        return 0
    end
    if not set -q argv[1]
        printf '%s\n' $usage >&2
        return 2
    end
    set -q _flag_quality; or set -l _flag_quality high
    set -l quality "$_flag_quality"
    set -l sampling 444
    switch "$quality"
        case high
            set quality 96
        case mid
            set quality 70
            set sampling 420
        case '*'
            if not string match -qr '^(100|[1-9][0-9]?)$' -- "$quality"
                echo 'sscrop: quality must be high, mid, or an integer from 1 to 100' >&2
                return 2
            end
    end

    set -l encoder (command -s cjpegli)
    if test -z "$encoder"
        set encoder "$HOME/.local/bin/cjpegli"
    end
    if not test -x "$encoder"
        echo 'sscrop: cjpegli is required' >&2
        return 1
    end

    if test (count $argv) -eq 2; and string match -qri '\.jpe?g$' -- "$argv[2]"
        __sscrop_one "$argv[1]" "$argv[2]" "$quality" "$sampling" "$encoder"
        return $status
    end

    set -l result 0
    for src in $argv
        set -l output (path change-extension '' -- "$src")' (cropped).jpg'
        __sscrop_one "$src" "$output" "$quality" "$sampling" "$encoder"; or set result 1
    end
    return $result
end

function __sscrop_one --argument-names src output quality sampling encoder
    set -l input (path resolve -- "$src")
    if not test -f "$input"
        echo "sscrop: could not find $src" >&2
        return 1
    end
    if test -e "$output"; or test -L "$output"
        echo "sscrop: output already exists: $output" >&2
        return 1
    end

    # A one-pixel black border also gives fully opaque screenshots a valid trim.
    set -l bounds (command magick "png:$input" +repage -alpha set -alpha extract -threshold 90% \
        -bordercolor black -border 1 -trim -format '%wx%h+%[fx:page.x-1]+%[fx:page.y-1]' info:)
    or return 1
    if not string match -qr '^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$' -- "$bounds"
        echo "sscrop: no pixels above 90% opacity in $src" >&2
        return 1
    end

    set -l temp (command mktemp -- (path dirname -- "$output")/.sscrop.XXXXXXXX)
    or return 1
    command magick "png:$input" +repage -crop "$bounds" +repage -background black -alpha remove -alpha off \
        -define png:color-type=2 -define png:compression-level=1 png:- \
        | "$encoder" - "$temp" -q "$quality" --chroma_subsampling "$sampling" --quiet
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
