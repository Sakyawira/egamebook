" Syntax for eGameBook writer files (*.egb.txt).
if exists('b:current_syntax')
  finish
endif

syntax case match

" Use Neovim's Dart syntax inside the embedded [[CODE]] blocks.
syntax include @egbDart syntax/dart.vim
unlet! b:current_syntax
syntax region egbDartCode matchgroup=egbBlockTag
      \ start=/^\s*\[\[CODE\]\]\s*$/
      \ end=/^\s*\[\[ENDCODE\]\]\s*$/
      \ keepend contains=@egbDart

syntax match egbComment /^\s*\/\/.*$/
syntax match egbField /^[A-Z_][A-Z_]*:/
syntax match egbObject /^\%(ROOM\|ACTION\|APPROACH\):/
syntax match egbReference /\$[A-Za-z_][A-Za-z_0-9]*/
syntax match egbChoice /^\s*\%(\*\s*\)\+.*$/ contains=egbChoiceHint,egbReference,egbInlineIf,egbInlineElse
syntax region egbChoiceHint start=/((/ end=/))/ oneline contained
syntax match egbGather /^\s*-\%(-\|\s\)*$/
syntax match egbGlue /<>/
syntax match egbInlineIf /\[\[IF\>[^]]*\]\]/
syntax match egbInlineElse /\[\[\%(ELSE\|ENDIF\)\]\]/
syntax match egbRuleTag /\[\[\%(RULESET\|ENDRULESET\|RULE\|ENDRULE\|THEN\)\]\]/
syntax match egbMusic /\c\[Music:\s*[^]]\+\]/
syntax match egbIllustration /\c\[Illustration:\s*[^]]\+\]/
syntax match egbClose /\c\[Close:\s*\%(Illustration\|Music\|All\)\s*\]/

highlight default link egbBlockTag PreProc
highlight default link egbComment Comment
highlight default link egbField Keyword
highlight default link egbObject Type
highlight default link egbReference Identifier
highlight default link egbChoice Statement
highlight default link egbChoiceHint Comment
highlight default link egbGather Label
highlight default link egbGlue Special
highlight default link egbInlineIf Conditional
highlight default link egbInlineElse Conditional
highlight default link egbRuleTag PreProc
highlight default link egbMusic String
highlight default link egbIllustration Special
highlight default link egbClose WarningMsg

let b:current_syntax = 'egamebook'
