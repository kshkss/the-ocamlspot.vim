" the-ocamlspot entry point
function! the_ocamlspot#main(query_type)
  let target = s:current_buffer_cursor()
  let result = s:run_ocaml_spot(target)

  try
    if a:query_type ==# 'type'
      call s:get_ocaml_type(result)
    elseif a:query_type ==# 'preview'
      call s:preview_definition(result)
    endif
  catch
    let g:Result = result
    if has_key(result, 'Error')
      echo result.Error
    else
      echoerr 'Unexpected Error!'
    endif
  endtry
endfunction

" get current [bufname, line, col]
" col is work fine with multibyte and is decremented for differnece from Emacs.
function! s:current_buffer_cursor()
  return [expand('%'), line('.'), virtcol('.') - 1]
endfunction

" run ocamlspot for a current buffer name and a cursor position
function! s:run_ocaml_spot(bufname_line_col)
  let bufname = a:bufname_line_col[0]
  let line = a:bufname_line_col[1]
  let col = a:bufname_line_col[2]
  let ocamlspot_cmd = printf('ocamlspot %s:l%dc%d 2>&1', bufname, line, col)
  let result = system(ocamlspot_cmd)
  let g:ocamlspot_result = result
  return s:parse_result(result)
endfunction

" parse result dictionary from ocamlspot result
function! s:parse_result(result)
  let result_dict = {}
  for line in split(a:result, "\n")
    let matches = matchlist(line, '\v(\w+)\: (.+)')
    if !empty(matches)
      let key = matches[1]
      let value = matches[2]
      let result_dict[key] = value
    endif
  endfor
  return result_dict
endfunction

" show type of the term under the cursor
function! s:get_ocaml_type(ocamlspot_result)
  if !s:try_echo_ocaml_val(a:ocamlspot_result)
    if !s:try_echo_ocaml_type(a:ocamlspot_result)
      if has_key(a:ocamlspot_result, 'Error')
        echo a:ocamlspot_result.Error
      else
        echo "no type found"
      endif
    endif
  endif

  let tree = get(a:ocamlspot_result, 'XTree', '')
  let tree_dict = s:parse_path_range(tree)
  if empty(tree_dict)
    return
  endif

  let range_regex = s:range_to_regex(tree_dict.range)

  if has_key(w:, 'tree_match')
    call matchdelete(w:tree_match)
  endif
  let w:tree_match = matchadd('PmenuSel', range_regex)
endfunction

function! s:try_echo_ocaml_val(ocamlspot_result)
  if has_key(a:ocamlspot_result, 'Val')
    echo 'Val: ' . a:ocamlspot_result.Val
    return 1 " success
  else
    return 0
  endif
endfunction

function! s:try_echo_ocaml_type(ocamlspot_result)
  if has_key(a:ocamlspot_result, 'Type')
    echo 'Type: ' . a:ocamlspot_result.Type
    return 1 " success
  else
    return 0
  endif
endfunction

" open preview window
function! s:preview_definition(ocamlspot_result)
  let spot = get(a:ocamlspot_result, 'Spot', '')

  if empty(spot)
    echo 'No definition found'
    call s:get_ocaml_type(a:ocamlspot_result)
    return
  endif

  let spot_dict = s:parse_path_range(spot)

  execute 'pedit +' . spot_dict.range.start[0] . ' ' . spot_dict.path
endfunction

function! s:parse_xtree(xtree) abort
  let matches = matchlist(a:spot, '\v\<(\f+):(all|[\-0-9lcb]+:[\-0-9lcb]+)\>')
  if empty(matches)
    return {}
  else
    let path = matches[1]
    let range = matches[2]
    let regurated_range = s:parse_range(range)
    return {'path': matches[1], 'range': regurated_range}
  endif
endfunction

function! s:parse_path_range(spot) abort
  let matches = matchlist(a:spot, '\v\<(\f+):(all|[\-0-9lcb]+:[\-0-9lcb]+)\>')
  if empty(matches)
    return {}
  else
    let path = matches[1]
    let range = matches[2]
    let regurated_range = s:parse_range(range)
    return {'path': matches[1], 'range': regurated_range}
  endif
endfunction

" parse range value and return regurated form Dictionary
" it returns {start: [sline, scol], end: [eline, ecol]}
function! s:parse_range(range) abort
    if a:range ==# 'all' || a:range ==# '-1:-1'
      return {
      \   'start' : ['1', '1'],
      \   'end'   : ['$', '$']
      \ }
    elseif a:range =~# '\v^l.+c.+b.+\:l.+c.+b.+$'
      let matches = matchlist(a:range, '\vl([\-0-9]+)c([\-0-9]+)b[\-0-9]+\:l([\-0-9]+)c([\-0-9]+)b[\-0-9]+')
      return {
      \ 'start' : [matches[1], matches[2]],
      \ 'end'   : [matches[3], matches[4]]
      \ }
    else
      throw 'Spot parsing error'
    endif
endfunction

function! s:range_to_regex(range)
  let sl = '%' . a:range.start[0] . 'l'
  let sc = '%' . (str2nr(a:range.start[1]) + 1) . 'v'

  let el = (a:range.end[0] ==# '$') ? '' : '%' . a:range.end[0] . 'l'
  let ec = (a:range.end[1] ==# '$') ? '' : '%' . (str2nr(a:range.end[1]) + 1) . 'v'

  return printf('\v(%s%s)\_.*(%s%s)', sl, sc, el, ec)
endfunction

" Balloon indication
function! the_ocamlspot#balloon_spotter()
  let target = s:balloon_buffer_cursor()
  let result = s:run_ocaml_spot(target)
  try
    if has_key(result, 'Val')
      return 'Val: ' . result.Val
    elseif has_key(result, 'Type')
      return 'Type: ' . result.Type
    elseif has_key(result, 'Error')
      return 'Error: ' . result.Error
    else
      return 'Error: no type found'
    endif
  catch
    " Nothing to do
  endt
endfunction

function! s:balloon_buffer_cursor()
  return [bufname(v:beval_bufnr), v:beval_lnum, v:beval_col - 1]
endfunction

