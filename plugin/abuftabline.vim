" Vim global plugin for rendering the buffer list in the tabline
" Licence:     The MIT License (MIT)
" Commit:      $Format:%H$
" {{{ Copyright (c) 2015 Aristotle Pagaltzis <pagaltzis@gmx.de>
" 
" Permission is hereby granted, free of charge, to any person obtaining a copy
" of this software and associated documentation files (the "Software"), to deal
" in the Software without restriction, including without limitation the rights
" to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
" copies of the Software, and to permit persons to whom the Software is
" furnished to do so, subject to the following conditions:
" 
" The above copyright notice and this permission notice shall be included in
" all copies or substantial portions of the Software.
" 
" THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
" IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
" FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
" AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
" LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
" OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
" THE SOFTWARE.
" }}}

if v:version < 700
	echoerr printf('Vim 7 is required for abuftabline (this is only %d.%d)',v:version/100,v:version%100)
	finish
endif

scriptencoding utf-8

hi default link abuftablineCurrent         TabLineSel
hi default link abuftablineActive          PmenuSel
hi default link abuftablineHidden          TabLine
hi default link abuftablineFill            TabLineFill
hi default link abuftablineModifiedCurrent abuftablineCurrent
hi default link abuftablineModifiedActive  abuftablineActive
hi default link abuftablineModifiedHidden  abuftablineHidden

let g:abuftabline_numbers    = get(g:, 'abuftabline_numbers',    0)
let g:abuftabline_indicators = get(g:, 'abuftabline_indicators', 0)
let g:abuftabline_separators = get(g:, 'abuftabline_separators', 0)
let g:abuftabline_show       = get(g:, 'abuftabline_show',       2)
let g:abuftabline_plug_max   = get(g:, 'abuftabline_plug_max',  10)
let g:abuftabline_ri_sep     = get(g:, 'abuftabline_right_separator', '')
let g:abuftabline_le_sep     = get(g:, 'abuftabline_left_separator', '')

function! abuftabline#user_buffers() " help buffers are always unlisted, but quickfix buffers are not
	return filter(range(1,bufnr('$')),'buflisted(v:val) && "quickfix" !=? getbufvar(v:val, "&buftype")')
endfunction

function! s:switch_buffer(bufnum, clicks, button, mod)
	execute 'buffer' a:bufnum
endfunction

function s:SID()
	return matchstr(expand('<sfile>'), '<SNR>\d\+_')
endfunction

let s:dirsep = fnamemodify(getcwd(),':p')[-1:]
let s:centerbuf = winbufnr(0)
let s:tablineat = has('tablineat')
let s:sid = s:SID() | delfunction s:SID
function! abuftabline#render()
	let show_num = g:abuftabline_numbers == 1
	let show_ord = g:abuftabline_numbers == 2
	let show_mod = g:abuftabline_indicators
	let lpad     = g:abuftabline_separators ? nr2char(0x23B8) : ' '

	let bufnums = abuftabline#user_buffers()
	let centerbuf = s:centerbuf " prevent tabline jumping around when non-user buffer current (e.g. help)

	" pick up data on all the buffers
	let tabs = []
	let path_tabs = []
	let tabs_per_tail = {}
	let currentbuf = winbufnr(0)
	let screen_num = 0
	for bufnum in bufnums
		let screen_num = show_num ? bufnum : show_ord ? screen_num + 1 : ''
		let tab = { 'num': bufnum, 'pre': '' }
		let tab.hilite = currentbuf == bufnum ? 'Current' : bufwinnr(bufnum) > 0 ? 'Active' : 'Hidden'
		if currentbuf == bufnum | let [centerbuf, s:centerbuf] = [bufnum, bufnum] | endif
		let bufpath = bufname(bufnum)
		if strlen(bufpath)
			let tab.path = fnamemodify(bufpath, ':p:~:.')
			let tab.sep = strridx(tab.path, s:dirsep, strlen(tab.path) - 2) " keep trailing dirsep
      if g:abuftabline_show_icon==1
        let tab.label = tab.path[tab.sep + 1:] . ' ' . WebDevIconsGetFileTypeSymbol(tab.path)
      else
        let tab.label = tab.path[tab.sep + 1:]
      endif
			let pre = screen_num 
			if getbufvar(bufnum, '&mod')
				let tab.hilite = 'Modified' . tab.hilite
				if show_mod | let pre = '+' . pre | endif
			endif
			if strlen(pre) | let tab.pre = pre . ' ' | endif
			let tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
			let path_tabs += [tab]
		elseif -1 < index(['nofile','acwrite'], getbufvar(bufnum, '&buftype')) " scratch buffer
			let tab.label = ( show_mod ? '!' . screen_num : screen_num ? screen_num . ' !' : '!' )
		else " unnamed file
			let tab.label = ( show_mod && getbufvar(bufnum, '&mod') ? '+' : '' )
			\             . ( screen_num ? screen_num : '*' )
		endif
		let tabs += [tab]
	endfor

	" disambiguate same-basename files by adding trailing path segments
	while len(filter(tabs_per_tail, 'v:val > 1'))
		let [ambiguous, tabs_per_tail] = [tabs_per_tail, {}]
		for tab in path_tabs
			if -1 < tab.sep && has_key(ambiguous, tab.label)
				" let tab.sep = strridx(tab.path, s:dirsep, tab.sep - 1)
				let tab.sep = strridx(tab.path, s:dirsep, tab.sep)
				let tab.label = tab.path[tab.sep + 1:]
			endif
			let tabs_per_tail[tab.label] = get(tabs_per_tail, tab.label, 0) + 1
		endfor
	endwhile

	" now keep the current buffer center-screen as much as possible:

	" 1. setup
	let lft = { 'lasttab':  0, 'cut':  '.', 'indicator': '<', 'width': 0, 'half': &columns / 2 +10 }
	let rgt = { 'lasttab': -1, 'cut': '.$', 'indicator': '>', 'width': 0, 'half': &columns - lft.half }

	" 2. sum the string lengths for the left and right halves
	let currentside = lft
	let lpad_width = strwidth(lpad)
	for tab in tabs
		let tab.width = lpad_width + strwidth(tab.pre) + strwidth(tab.label) + 10
		" let tab.width = lpad_width + strwidth(tab.pre) + strwidth(tab.label) - 2
		let tab.label = g:abuftabline_le_sep . tab.pre . substitute(strtrans(tab.label), '%', '%%', 'g') . g:abuftabline_ri_sep
		if centerbuf == tab.num
			let halfwidth = tab.width / 2 
			let lft.width += halfwidth +20
			let rgt.width += tab.width - halfwidth
			let currentside = rgt
			continue
		endif
		let currentside.width += tab.width
	endfor
	if currentside is lft " centered buffer not seen?
		" then blame any overflow on the right side, to protect the left
		" let [lft.width, rgt.width] = [0, lft.width]
		let [lft.width, rgt.width] = [0, lft.width]
	endif

	" 3. toss away tabs and pieces until all fits:
	if ( lft.width + rgt.width ) > &columns
		let oversized
		\ = lft.width < lft.half ? [ [ rgt, &columns - lft.width  ] ]
		\ : rgt.width < rgt.half ? [ [ lft, &columns - rgt.width  ] ]
		\ :                        [ [ lft, lft.half ], [ rgt, rgt.half  ] ]
		for [side, budget] in oversized
			let delta = side.width - budget
			" toss entire tabs to close the distance
			while delta >= tabs[side.lasttab].width
				let delta -= remove(tabs, side.lasttab).width
			endwhile
			" then snip at the last one to make it fit
			let endtab = tabs[side.lasttab]
			while delta > ( endtab.width - strwidth(strtrans(endtab.label)) )
				let endtab.label = substitute(endtab.label, side.cut, '', '')
			endwhile
			let endtab.label = substitute(endtab.label, side.cut, side.indicator, '')
		endfor
	endif

	if len(tabs) | let tabs[0].label = substitute(tabs[0].label, '|', ' ', '') | endif

	let swallowclicks = '%'.(1 + tabpagenr('$')).'X'
	return s:tablineat
		\ ? join(map(tabs,'"%#abuftabline".v:val.hilite."#" . "%".v:val.num."@'.s:sid.'switch_buffer@" . strtrans(v:val.label)'),'') . '%#abuftablineFill#' . swallowclicks
		\ : swallowclicks . join(map(tabs,'"%#abuftabline".v:val.hilite."#" . strtrans(v:val.label)'),'') . '%#abuftablineFill#'
endfunction

function! abuftabline#update(zombie)
	set tabline=
	if tabpagenr('$') > 1 | set guioptions+=e showtabline=2 | return | endif
	set guioptions-=e
	if 0 == g:abuftabline_show
		set showtabline=1
		return
	elseif 1 == g:abuftabline_show
		" account for BufDelete triggering before buffer is actually deleted
		let bufnums = filter(abuftabline#user_buffers(), 'v:val != a:zombie')
		let &g:showtabline = 1 + ( len(bufnums) > 1 )
	elseif 2 == g:abuftabline_show
		set showtabline=2
	endif
	set tabline=%!abuftabline#render()
endfunction

augroup abuftabline
autocmd!
autocmd VimEnter  * call abuftabline#update(0)
autocmd TabEnter  * call abuftabline#update(0)
autocmd BufAdd    * call abuftabline#update(0)
autocmd FileType qf call abuftabline#update(0)
autocmd BufDelete * call abuftabline#update(str2nr(expand('<abuf>')))
augroup END

for s:n in range(1, g:abuftabline_plug_max) + ( g:abuftabline_plug_max > 0 ? [-1] : [] )
	let s:b = s:n == -1 ? -1 : s:n - 1
	execute printf("noremap <silent> <Plug>abuftabline.Go(%d) :<C-U>exe 'b'.get(abuftabline#user_buffers(),%d,'')<cr>", s:n, s:b)
endfor
unlet! s:n s:b

if v:version < 703
	function s:transpile()
		let [ savelist, &list ] = [ &list, 0 ]
		redir => src
			silent function abuftabline#render
		redir END
		let &list = savelist
		let src = substitute(src, '\n\zs[0-9 ]*', '', 'g')
		let src = substitute(src, 'strwidth(strtrans(\([^)]\+\)))', 'strlen(substitute(\1, ''\p\|\(.\)'', ''x\1'', ''g''))', 'g')
		return src
	endfunction
	exe "delfunction abuftabline#render\n" . s:transpile()
	delfunction s:transpile
endif
