" sleuth.vim - Heuristically set buffer options
" Maintainer:   Tim Pope <http://tpo.pe/>
" Version:      2.0
" GetLatestVimScripts: 4375 1 :AutoInstall: sleuth.vim

if exists("#polyglot-sleuth")
    au! polyglot-sleuth
    augroup! polyglot-sleuth
    unlet! g:loaded_sleuth
    let s:polyglot = 1
en

if exists("g:loaded_sleuth") || v:version < 700 || &cp
    finish
en
let g:loaded_sleuth = 1
lockvar g:loaded_sleuth

fun! s:Warn(msg) abort
    echohl WarningMsg
    echo a:msg
    echohl NONE
    return ''
endf

if exists('+shellslash')
    fun! s:Slash(path) abort
        return tr(a:path, '\', '/')
    endf
el
    fun! s:Slash(path) abort
        return a:path
    endf
en

fun! s:Guess(source, detected, lines) abort
    let has_heredocs = a:detected.filetype =~# '^\%(perl\|php\|ruby\|[cz]\=sh\|bash\)$'
    let options = {}
    let heuristics = {'spaces': 0, 'hard': 0, 'soft': 0, 'checked': 0, 'indents': {}}
    let tabstop = get(a:detected.options, 'tabstop', get(a:detected.defaults, 'tabstop', [4]))[0]
    "\ let tabstop = get(a:detected.options, 'tabstop', get(a:detected.defaults, 'tabstop', [8]))[0]
    let softtab = repeat(' ', tabstop)
    let waiting_on = ''
    let prev_indent = -1
    let prev_line = ''

    for line in a:lines
        if len(waiting_on)
            if line =~# waiting_on
                let waiting_on = ''
                let prev_indent = -1
                let prev_line = ''
            en
            continue
        elseif line =~# '^\s*$'
            continue
        elseif a:detected.filetype ==# 'python' && prev_line[-1:-1] =~# '[[\({]'
            let prev_indent = -1
            let prev_line = ''
            continue
        elseif line =~# '^=\w' && line !~# '^=\%(end\|cut\)\>'
            let waiting_on = '^=\%(end\|cut\)\>'
        elseif line =~# '^@@\+ -\d\+,\d\+ '
            let waiting_on = '^$'
        elseif line !~# '[/<"`]'
            " No need to do other checks
        elseif line =~# '^\s*/\*' && line !~# '\*/'
            let waiting_on = '\*/'
        elseif line =~# '^\s*<\!--' && line !~# '-->'
            let waiting_on = '-->'
        elseif line =~# '^[^"]*"""[^"]*$'
            let waiting_on = '^[^"]*"""[^"]*$'
        elseif a:detected.filetype ==# 'go' && line =~# '^[^`]*`[^`]*$'
            let waiting_on = '^[^`]*`[^`]*$'
        elseif has_heredocs
            let waiting_on = matchstr(line, '<<\s*\([''"]\=\)\zs\w\+\ze\1[^''"`<>]*$')
            if len(waiting_on)
                let waiting_on = '^' . waiting_on . '$'
            en
        en

        let indent = len(matchstr(substitute(line, '\t', softtab, 'g'), '^ *'))
        if line =~# '^\t'
            let heuristics.hard += 1
        elseif line =~# '^' . softtab
            let heuristics.soft += 1
        en
        if line =~# '^  '
            let heuristics.spaces += 1
        en
        let increment = prev_indent < 0 ? 0 : indent - prev_indent
        let prev_indent = indent
        let prev_line = line
        if increment > 1 && (increment < 4 || increment % 4 == 0)
            if has_key(heuristics.indents, increment)
                let heuristics.indents[increment] += 1
            el
                let heuristics.indents[increment] = 1
            en
            let heuristics.checked += 1
        en
        if heuristics.checked >= 32 && (heuristics.hard > 3 || heuristics.soft > 3) && get(heuristics.indents, increment) * 2 > heuristics.checked
            if heuristics.spaces
                break
            elseif !exists('no_space_indent')
                let no_space_indent = stridx("\n" . join(a:lines, "\n"), "\n  ") < 0
                if no_space_indent
                    break
                en
            en
            break
        en
    endfor

    let a:detected.heuristics[a:source] = heuristics

    let max_frequency = 0
    for [shiftwidth, frequency] in items(heuristics.indents)
        if frequency > max_frequency || frequency == max_frequency && +shiftwidth < get(options, 'shiftwidth')
            let options.shiftwidth = +shiftwidth
            let max_frequency = frequency
        en
    endfor

    if heuristics.hard && !heuristics.spaces &&
                \ !has_key(a:detected.options, 'tabstop')
        let options = {'expandtab': 0, 'shiftwidth': 0}
    elseif heuristics.hard > heuristics.soft
        let options.expandtab = 0
        let options.tabstop = tabstop
    el
        if heuristics.soft
            let options.expandtab = 1
        en
        if heuristics.hard || has_key(a:detected.options, 'tabstop') ||
                    \ stridx(join(a:lines, "\n"), "\t") >= 0
            let options.tabstop = tabstop
        elseif !&g:shiftwidth && has_key(options, 'shiftwidth') &&
                    \ !has_key(a:detected.options, 'shiftwidth')
            let options.tabstop = options.shiftwidth
            let options.shiftwidth = 0
        en
    en

    call map(options, '[v:val, a:source]')
    call extend(a:detected.options, options, 'keep')
endf

fun! s:Capture(cmd) abort
    redir => capture
    silent execute a:cmd
    redir END
    return capture
endf

let s:modeline_numbers = {
            \ 'shiftwidth': 'shiftwidth', 'sw': 'shiftwidth',
            \ 'tabstop': 'tabstop', 'ts': 'tabstop',
            \ 'textwidth': 'textwidth', 'tw': 'textwidth',
            \ }
let s:modeline_booleans = {
            \ 'expandtab': 'expandtab', 'et': 'expandtab',
            \ 'fixendofline': 'fixendofline', 'fixeol': 'fixendofline',
            \ }
fun! s:ParseOptions(declarations, into, ...) abort
    for option in a:declarations
        if has_key(s:modeline_booleans, matchstr(option, '^\%(no\)\=\zs\w\+$'))
            let a:into[s:modeline_booleans[matchstr(option, '^\%(no\)\=\zs\w\+')]] = [option !~# '^no'] + a:000
        elseif has_key(s:modeline_numbers, matchstr(option, '^\w\+\ze=[1-9]\d*$'))
            let a:into[s:modeline_numbers[matchstr(option, '^\w\+')]] = [str2nr(matchstr(option, '\d\+$'))] + a:000
        elseif option =~# '^\%(ft\|filetype\)=[[:alnum:]._-]*$'
            let a:into.filetype = [matchstr(option, '=\zs.*')] + a:000
        en
        if option ==# 'nomodeline' || option ==# 'noml'
            return 1
        en
    endfor
    return 0
endf

fun! s:ModelineOptions() abort
    let options = {}
    if !&l:modeline && (&g:modeline || s:Capture('setlocal') =~# '\\\@<![[:space:]]nomodeline\>')
        return options
    en
    let modelines = get(b:, 'sleuth_modelines', get(g:, 'sleuth_modelines', 5))
    if line('$') > 2 * modelines
        let lnums = range(1, modelines) + range(line('$') - modelines + 1, line('$'))
    el
        let lnums = range(1, line('$'))
    en
    for lnum in lnums
        if s:ParseOptions(split(matchstr(getline(lnum),
                    \ '\%(\S\@<!vim\=\|\s\@<=ex\):\s*\(set\= \zs[^:]\+\|\zs.*\S\)'),
                    \ '[[:space:]:]\+'), options, 'modeline', lnum)
            break
        en
    endfor
    return options
endf

let s:fnmatch_replacements = {
            \ '.': '\.', '\%': '%', '\(': '(', '\)': ')', '\{': '{', '\}': '}', '\_': '_',
            \ '?': '[^/]', '*': '[^/]*', '/**/*': '/.*', '/**/': '/\%(.*/\)\=', '**': '.*'}
fun! s:FnmatchReplace(pat) abort
    if has_key(s:fnmatch_replacements, a:pat)
        return s:fnmatch_replacements[a:pat]
    elseif len(a:pat) ==# 1
        return '\' . a:pat
    elseif a:pat =~# '^{[+-]\=\d\+\.\.[+-]\=\d\+}$'
        return '\%(' . join(range(matchstr(a:pat, '[+-]\=\d\+'), matchstr(a:pat, '\.\.\zs[+-]\=\d\+')), '\|') . '\)'
    elseif a:pat =~# '^{.*\\\@<!\%(\\\\\)*,.*}$'
        return '\%(' . substitute(a:pat[1:-2], ',\|\%(\\.\|{[^\{}]*}\|[^,]\)*', '\=submatch(0) ==# "," ? "\\|" : s:FnmatchTranslate(submatch(0))', 'g') . '\)'
    elseif a:pat =~# '^{.*}$'
        return '{' . s:FnmatchTranslate(a:pat[1:-2]) . '}'
    elseif a:pat =~# '^\[!'
        return '[^' . a:pat[2:-1]
    el
        return a:pat
    en
endf

fun! s:FnmatchTranslate(pat) abort
    return substitute(a:pat, '\\.\|/\*\*/\*\=\|\*\*\=\|\[[!^]\=\]\=[^]/]*\]\|{\%(\\.\|[^{}]\|{[^\{}]*}\)*}\|[?.\~^$[]', '\=s:FnmatchReplace(submatch(0))', 'g')
endf

fun! s:ReadEditorConfig(absolute_path) abort
    try
        let lines = readfile(a:absolute_path)
    catch
        let lines = []
    endtry
    let prefix = '\m\C^' . escape(fnamemodify(a:absolute_path, ':h'), '][^$.*\~')
    let preamble = {}
    let pairs = preamble
    let sections = []
    let i = 0
    while i < len(lines)
        let line = lines[i]
        let i += 1
        let line = substitute(line, '^[[:space:]]*\|[[:space:]]*\%([^[:space:]]\@<![;#].*\)\=$', '', 'g')
        let match = matchlist(line, '^\%(\[\(\%(\\.\|[^\;#]\)*\)\]\|\([^[:space:]]\@=[^;#=:]*[^;#=:[:space:]]\)[[:space:]]*[=:][[:space:]]*\(.*\)\)$')
        if len(get(match, 2, ''))
            let pairs[tolower(match[2])] = [match[3], a:absolute_path, i]
        elseif len(get(match, 1, '')) && len(get(match, 1, '')) <= 4096
            if match[1] =~# '^/'
                let pattern = match[1]
            elseif match[1] =~# '/'
                let pattern = '/' . match[1]
            el
                let pattern = '/**/' . match[1]
            en
            let pairs = {}
            call add(sections, [prefix . s:FnmatchTranslate(pattern) . '$', pairs])
        en
    endwhile
    return [preamble, sections]
endf

let s:editorconfig_cache = {}
fun! s:DetectEditorConfig(absolute_path, ...) abort
    if empty(a:absolute_path)
        return [{}, '']
    en
    let root = ''
    let tail = a:0 ? a:1 : '.editorconfig'
    let dir = fnamemodify(a:absolute_path, ':h')
    let previous_dir = ''
    let sections = []
    let overrides = get(g:, 'sleuth_editorconfig_overrides', {})
    while dir !=# previous_dir && dir !~# '^//\%([^/]\+/\=\)\=$'
        let head = substitute(dir, '/\=$', '/', '')
        let read_from = get(overrides, head . tail, get(overrides, head, head . tail))
        if type(read_from) == type('') && read_from !=# head . tail && read_from !~# '^/\|^\a\+:\|^$'
            let read_from = simplify(head . read_from)
        en
        let ftime = type(read_from) == type('') ? getftime(read_from) : -1
        let [cachetime; econfig] = get(s:editorconfig_cache, read_from, [-1, {}, []])
        if ftime != cachetime
            let econfig = s:ReadEditorConfig(read_from)
            let s:editorconfig_cache[read_from] = [ftime] + econfig
            lockvar! s:editorconfig_cache[read_from]
            unlockvar s:editorconfig_cache[read_from]
        en
        call extend(sections, econfig[1], 'keep')
        if get(econfig[0], 'root', [''])[0] ==? 'true'
            let root = head
            break
        en
        let previous_dir = dir
        let dir = fnamemodify(dir, ':h')
    endwhile

    let config = {}
    for [pattern, pairs] in sections
        if a:absolute_path =~# pattern
            call extend(config, pairs)
        en
    endfor

    return [config, root]
endf

let s:editorconfig_bomb = {
            \ 'utf-8':     0,
            \ 'utf-8-bom': 1,
            \ 'utf-16be':  1,
            \ 'utf-16le':  1,
            \ 'latin1':    0,
            \ }

let s:editorconfig_fileformat = {
            \ 'cr':   'mac',
            \ 'crlf': 'dos',
            \ 'lf':   'unix',
            \ }

fun! s:EditorConfigToOptions(pairs) abort
    let options = {}
    let pairs = map(copy(a:pairs), 'v:val[0]')
    let sources = map(copy(a:pairs), 'v:val[1:-1]')
    call filter(pairs, 'v:val !=? "unset"')

    if get(pairs, 'indent_style', '') ==? 'tab'
        let options.expandtab = [0] + sources.indent_style
    elseif get(pairs, 'indent_style', '') ==? 'space'
        let options.expandtab = [1] + sources.indent_style
    en

    if get(pairs, 'indent_size', '') =~? '^[1-9]\d*$\|^tab$'
        let options.shiftwidth = [str2nr(pairs.indent_size)] + sources.indent_size
        if &g:shiftwidth == 0 && !has_key(pairs, 'tab_width') && pairs.indent_size !=? 'tab'
            let options.tabstop = options.shiftwidth
            let options.shiftwidth = [0] + sources.indent_size
        en
    en

    if get(pairs, 'tab_width', '') =~? '^[1-9]\d*$'
        let options.tabstop = [str2nr(pairs.tab_width)] + sources.tab_width
        if !has_key(pairs, 'indent_size') && get(pairs, 'indent_style', '') ==? 'tab'
            let options.shiftwidth = [0] + options.tabstop[1:-1]
        en
    en

    if get(pairs, 'max_line_length', '') =~? '^[1-9]\d*$\|^off$'
        let options.textwidth = [str2nr(pairs.max_line_length)] + sources.max_line_length
    en

    if get(pairs, 'insert_final_newline', '') =~? '^true$\|^false$'
        let options.endofline = [pairs.insert_final_newline ==? 'true'] + sources.insert_final_newline
        let options.fixendofline = copy(options.endofline)
    en

    let eol = tolower(get(pairs, 'end_of_line', ''))
    if has_key(s:editorconfig_fileformat, eol)
        let options.fileformat = [s:editorconfig_fileformat[eol]] + sources.end_of_line
    en

    let charset = tolower(get(pairs, 'charset', ''))
    if has_key(s:editorconfig_bomb, charset)
        let options.bomb = [s:editorconfig_bomb[charset]] + sources.charset
        let options.fileencoding = [substitute(charset, '\C-bom$', '', '')] + sources.charset
    en

    let filetype = tolower(get(pairs, 'vim_filetype', 'unset'))
    if filetype !=# 'unset' && filetype =~# '^[.a-z0-9_-]*$'
        let options.filetype = [substitute(filetype, '^\.\+\|\.\+$', '', 'g')] + sources.vim_filetype
    en

    return options
endf

fun! s:Ready(detected) abort
    return has_key(a:detected.options, 'expandtab') && has_key(a:detected.options, 'shiftwidth')
endf

let s:booleans = {'expandtab': 1, 'fixendofline': 1, 'endofline': 1, 'bomb': 1}
let s:safe_options = ['expandtab', 'shiftwidth', 'tabstop', 'textwidth', 'fixendofline']
let s:all_options = s:safe_options + ['endofline', 'fileformat', 'fileencoding', 'bomb']
let s:short_options = {
            \ 'expandtab': 'et', 'shiftwidth': 'sw', 'tabstop': 'ts',
            \ 'textwidth': 'tw', 'fixendofline': 'fixeol',
            \ 'endofline': 'eol', 'fileformat': 'ff', 'fileencoding': 'fenc'}

fun! s:Apply(detected, permitted_options) abort
    let options = extend(copy(a:detected.defaults), a:detected.options)
    if get(a:detected.defaults, 'shiftwidth', [1])[0] == 0 && get(options, 'shiftwidth', [0])[0] != 0 && !has_key(a:detected.declared, 'tabstop')
        let options.tabstop = options.shiftwidth
        let options.shiftwidth = a:detected.defaults.shiftwidth
    en
    if has_key(options, 'shiftwidth') && !has_key(options, 'expandtab')
        let options.expandtab = [stridx(join(getline(1, 256), "\n"), "\t") == -1, a:detected.bufname]
    en
    if !exists('*shiftwidth') && !get(options, 'shiftwidth', [1])[0]
        let options.shiftwidth = [get(options, 'tabstop', [&tabstop])[0]] + options.shiftwidth[1:-1]
    en
    let msg = ''
    let cmd = 'setlocal'
    for option in a:permitted_options
        if !exists('&' . option) || !has_key(options, option) ||
                    \ !&l:modifiable && index(s:safe_options, option) == -1
            continue
        en
        let value = options[option]
        if has_key(s:booleans, option)
            let setting = (value[0] ? '' : 'no') . option
        el
            let setting = option . '=' . value[0]
        en
        if getbufvar('', '&' . option) !=# value[0] || index(s:safe_options, option) >= 0
            let cmd .= ' ' . setting
        en
        if !&verbose
            if has_key(s:booleans, option)
                let msg .= ' ' . (value[0] ? '' : 'no') . get(s:short_options, option, option)
            el
                let msg .= ' ' . get(s:short_options, option, option) . '=' . value[0]
            en
            continue
        en
        if len(value) > 1
            if value[1] ==# a:detected.bufname
                let file = '%'
            el
                let file = value[1] =~# '/' ? fnamemodify(value[1], ':~:.') : value[1]
                if file !=# value[1] && file[0:0] !=# '~'
                    let file = './' . file
                en
            en
            if len(value) > 2
                let file .= ' line ' . value[2]
            en
            echo printf(':setl  %-21s " from %s', setting, file)
        el
            echo ':setl  ' . setting
        en
    endfor
    if !&verbose && !empty(msg)
        echo ':setlocal' . msg
    en
    if has_key(options, 'shiftwidth')
        let cmd .= ' softtabstop=' . (exists('*shiftwidth') ? -1 : options.shiftwidth[0])
    el
        call s:Warn(':Sleuth failed to detect indent settings')
    en
    return cmd ==# 'setlocal' ? '' : cmd
endf

fun! s:UserOptions(ft, name) abort
    let source = 'g:sleuth_' . a:ft . '_' . a:name
    let val = get(g:, source[2 : -1])
    let options = {}
    if type(val) == type('')
        call s:ParseOptions(split(substitute(val, '\S\@<![=+]\S\@=', 'ft=', 'g'), '[[:space:]:,]\+'), options, source)
        if has_key(options, 'filetype')
            call extend(options, s:UserOptions(remove(options, 'filetype')[0], a:name), 'keep')
        en
        if has_key(options, 'tabstop')
            call extend(options, {'shiftwidth': [0, source], 'expandtab': [0, source]}, 'keep')
        elseif has_key(options, 'shiftwidth')
            call extend(options, {'expandtab': [1, source]}, 'keep')
        en
    elseif type(val) == type([])
        call s:ParseOptions(val, options, source)
    el
        return {}
    en
    call filter(options, 'index(s:safe_options, v:key) >= 0')
    return options
endf

fun! s:DetectDeclared() abort
    let detected = {'bufname': s:Slash(@%), 'declared': {}}
    let absolute_or_empty = detected.bufname =~# '^$\|^\a\+:\|^/'
    if &l:buftype =~# '^\%(nowrite\)\=$' && !absolute_or_empty
        let detected.bufname = s:Slash(getcwd()) . '/' . detected.bufname
        let absolute_or_empty = 1
    en
    let detected.path = absolute_or_empty ? detected.bufname : ''
    let pre = substitute(matchstr(detected.path, '^\a\a\+\ze:'), '^\a', '\u&', 'g')
    if len(pre) && exists('*' . pre . 'Real')
        let detected.path = s:Slash(call(pre . 'Real', [detected.path]))
    en

    try
        if len(detected.path) && exists('*ExcludeBufferFromDiscovery') && !empty(ExcludeBufferFromDiscovery(detected.path, 'sleuth'))
            let detected.path = ''
        en
    catch
    endtry
    let [detected.editorconfig, detected.root] = s:DetectEditorConfig(detected.path)
    call extend(detected.declared, s:EditorConfigToOptions(detected.editorconfig))
    call extend(detected.declared, s:ModelineOptions())
    return detected
endf

fun! s:DetectHeuristics(into) abort
    let detected = a:into
    let filetype = split(&l:filetype, '\.', 1)[0]
    if get(detected, 'filetype', '*') ==# filetype
        return detected
    en
    let detected.filetype = filetype
    let options = copy(detected.declared)
    let detected.options = options
    let detected.heuristics = {}
    if has_key(detected, 'patterns')
        call remove(detected, 'patterns')
    en
    let detected.defaults = s:UserOptions(filetype, 'defaults')
    if empty(filetype) || !get(b:, 'sleuth_automatic', 1) || empty(get(b:, 'sleuth_heuristics', get(g:, 'sleuth_' . filetype . '_heuristics', get(g:, 'sleuth_heuristics', 1))))
        return detected
    en
    if s:Ready(detected)
        return detected
    en

    let lines = getline(1, 1024)
    call s:Guess(detected.bufname, detected, lines)
    if s:Ready(detected)
        return detected
    elseif get(options, 'shiftwidth', [4])[0] < 4 && stridx(join(lines, "\n"), "\t") == -1
        let options.expandtab = [1, detected.bufname]
        return detected
    en
    let dir = len(detected.path) ? fnamemodify(detected.path, ':h') : ''
    let root = len(detected.root) ? fnamemodify(detected.root, ':h') : dir ==# s:Slash(expand('~')) ? dir : fnamemodify(dir, ':h')
    if detected.bufname =~# '^\a\a\+:' || root ==# '.' || !isdirectory(root)
        let dir = ''
    en
    let c = get(b:, 'sleuth_neighbor_limit', get(g:, 'sleuth_neighbor_limit', 8))
    if c <= 0 || empty(dir)
        let detected.patterns = []
    elseif type(get(g:, 'sleuth_' . detected.filetype . '_globs')) == type([])
        let detected.patterns = get(g:, 'sleuth_' . detected.filetype . '_globs')
    el
        let detected.patterns = ['*' . matchstr(detected.bufname, '/\@<!\.[^][{}*?$~\`./]\+$')]
        if detected.patterns ==# ['*']
            let detected.patterns = [matchstr(detected.bufname, '/\zs[^][{}*?$~\`/]\+\ze/\=$')]
            let dir = fnamemodify(dir, ':h')
            if empty(detected.patterns[0])
                let detected.patterns = []
            en
        en
    en
    while c > 0 && dir !~# '^$\|^//[^/]*$' && dir !=# fnamemodify(dir, ':h')
        for pattern in detected.patterns
            for neighbor in split(glob(dir.'/'.pattern), "\n")[0:7]
                if neighbor !=# detected.path && filereadable(neighbor)
                    call s:Guess(neighbor, detected, readfile(neighbor, '', 256))
                    let c -= 1
                en
                if s:Ready(detected)
                    return detected
                en
                if c <= 0
                    break
                en
            endfor
            if c <= 0
                break
            en
        endfor
        if len(dir) <= len(root)
            break
        en
        let dir = fnamemodify(dir, ':h')
    endwhile
    if !has_key(options, 'shiftwidth')
        let detected.options = copy(detected.declared)
    en
    return detected
endf

fun! s:Init(redetect, unsafe, do_filetype) abort
    if !a:redetect && exists('b:sleuth.defaults')
        let detected = b:sleuth
    en
    unlet! b:sleuth
    if &l:buftype !~# '^\%(nowrite\|nofile\|acwrite\)\=$'
        return s:Warn(':Sleuth disabled for buftype=' . &l:buftype)
    en
    if &l:filetype ==# 'netrw'
        return s:Warn(':Sleuth disabled for filetype=' . &l:filetype)
    en
    if &l:binary
        return s:Warn(':Sleuth disabled for binary files')
    en
    if !exists('detected')
        let detected = s:DetectDeclared()
    en
    let setfiletype = ''
    if a:do_filetype && has_key(detected.declared, 'filetype')
        let filetype = detected.declared.filetype[0]
        if filetype !=# &l:filetype || empty(filetype)
            let setfiletype = 'setl  filetype=' . filetype
        el
            let setfiletype = 'setfiletype ' . filetype
        en
    en
    exe setfiletype
    call s:DetectHeuristics(detected)
    let cmd = s:Apply(detected, (a:do_filetype ? ['filetype'] : []) + (a:unsafe ? s:all_options : s:safe_options))
    let b:sleuth = detected
    if exists('s:polyglot')
        call s:Warn('Charlatan :Sleuth implementation in vim-polyglot has been found and disabled.')
        call s:Warn('To get rid of this message, uninstall vim-polyglot, or disable the')
        call s:Warn('corresponding feature in your vimrc:')
        call s:Warn('        let g:polyglot_disabled = ["autoindent"]')
    en
    return cmd
endf

fun! s:AutoInit() abort
    silent return s:Init(1, 1, 1)
endf

fun! s:Sleuth(line1, line2, range, bang, mods, args) abort
    let safe = a:bang || expand("<sfile>") =~# '\%(^\|\.\.\)FileType '
    return s:Init(!a:bang, !safe, !safe)
endf

setglobal smarttab

if !exists('g:did_indent_on') && !get(g:, 'sleuth_no_filetype_indent_on')
    filetype indent on
elseif !exists('g:did_load_filetypes')
    filetype on
en

fun! SleuthIndicator() abort
    let sw = &shiftwidth ? &shiftwidth : &tabstop
    if &expandtab
        let ind = 'sw='.sw
    elseif &tabstop == sw
        let ind = 'ts='.&tabstop
    el
        let ind = 'sw='.sw.',ts='.&tabstop
    en
    if &textwidth
        let ind .= ',tw='.&textwidth
    en
    if exists('&fixendofline') && !&fixendofline && !&endofline
        let ind .= ',noeol'
    en
    return ind
endf

aug  sleuth
    au!
    au BufNewFile,BufReadPost * nested
                \ if get(g:, 'sleuth_automatic', 1)
                \ | exe s:AutoInit() | endif
    au BufFilePost * nested
                \ if (@% !~# '^!' || exists('b:sleuth')) && get(g:, 'sleuth_automatic', 1)
                \ | exe s:AutoInit() | endif
    au FileType * nested
                \ if exists('b:sleuth') | silent exe s:Init(0, 0, 0) | endif
    au User Flags call Hoist('buffer', 5, 'SleuthIndicator')
aug  END

com!  -bar -bang
    \ Sleuth
    \ exe s:Sleuth(<line1>, <count>, +"<range>", <bang>0, "<mods>", <q-args>)
